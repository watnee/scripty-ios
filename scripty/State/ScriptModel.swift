//
//  ScriptModel.swift
//  scripty
//
//  State for one open screenplay: its blocks, characters, undo/redo
//  status, and a background sync-polling task that picks up edits made
//  elsewhere (e.g. in the web app).
//

import Foundation
import Observation

@Observable @MainActor
final class ScriptModel {
    let app: AppModel
    private(set) var project: Project

    private(set) var blocks: [Block] = []
    private(set) var blocksLinks = HALLinks()
    private(set) var characters: [Person] = []
    private(set) var charactersLinks = HALLinks()
    private(set) var canViewCharacters = true

    /// The server offers a first block only on an empty script the user may edit.
    var canStartScript: Bool {
        blocksLinks[.createInitial] != nil
    }

    private(set) var undoRedo: UndoRedoStatus?
    private(set) var isLoading = false
    var errorMessage: String?

    /// Set while an editor sheet is open so a sync refresh doesn't clobber
    /// in-progress typing.
    var hasActiveEdit = false

    private var lastRevision: Int64 = 0
    private var syncTask: Task<Void, Never>?

    private static let syncInterval: Duration = .seconds(5)

    init(app: AppModel, project: Project) {
        self.app = app
        self.project = project
    }

    // MARK: - Loading

    func loadEverything() async {
        isLoading = true
        defer { isLoading = false }
        await loadBlocks()
        await loadCharacters()
        await refreshUndoRedo()
    }

    func loadBlocks() async {
        guard let link = project.link(.blocks) else { return }
        do {
            let collection: HALCollection<Block> = try await app.client.fetch(from: link)
            blocks = collection.items.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
            blocksLinks = collection.links
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    func loadCharacters() async {
        guard let link = project.link(.characters) else { return }
        do {
            let collection: HALCollection<Person> = try await app.client.fetch(from: link)
            characters = collection.items.sorted { $0.displayName < $1.displayName }
            charactersLinks = collection.links
            canViewCharacters = true
        } catch APIError.forbidden {
            canViewCharacters = false
        } catch {
            report(error)
        }
    }

    // MARK: - Block mutations (all gated by link presence)

    @discardableResult
    func createBlock(content: String, type: BlockType, personId: Int?) async -> Bool {
        guard let link = blocksLinks[.selfRel] ?? project.link(.blocks) else { return false }
        do {
            let _: Block = try await app.client.fetch(
                from: link, method: "POST",
                body: CreateBlockCommand(content: content,
                                         personId: personId,
                                         projectId: project.id,
                                         type: type.rawValue))
            await loadBlocks()
            await refreshUndoRedo()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    @discardableResult
    func updateBlock(_ block: Block, content: String, personId: Int?, tags: String?) async -> Bool {
        guard let link = block.link(.update) else { return false }
        do {
            let updated: Block = try await app.client.fetch(
                from: link, method: "PUT",
                body: EditBlockCommand(content: content, personId: personId, tags: tags))
            replace(updated)
            await refreshUndoRedo()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    func deleteBlock(_ block: Block) async {
        guard let link = block.link(.delete) else { return }
        do {
            try await app.client.data(for: link, method: "DELETE")
            blocks.removeAll { $0.id == block.id }
            await refreshUndoRedo()
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    // MARK: - Inline editing

    /// Saves a row's text, if it actually changed. Called when a row loses focus.
    @discardableResult
    func commit(_ block: Block, content: String) async -> Bool {
        guard content != (block.content ?? "") else { return true }
        guard let link = block.link(.update) else { return false }
        do {
            let updated: Block = try await app.client.fetch(
                from: link, method: "PUT",
                body: EditBlockCommand(content: content,
                                       personId: block.personId,
                                       tags: block.tags))
            replace(updated)
            await refreshUndoRedo()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Return: leaves `before` in the block and carries `after` into a new one
    /// below it. With the caret at the end of the line — the common case —
    /// `after` is empty and this simply opens the next element.
    ///
    /// Returns the new block so the caller can move the caret into it.
    func splitBlock(_ block: Block, before: String, after: String) async -> Block? {
        guard block.hasLink(.createBelow) else { return nil }
        if before != (block.content ?? "") {
            guard await commit(block, content: before) else { return nil }
        }
        return await createBlockBelow(block, content: after, type: block.blockType.nextOnEnter)
    }

    /// Inserts a block below `block`, the way the web editor does.
    @discardableResult
    func createBlockBelow(_ block: Block, content: String = "", type: BlockType) async -> Block? {
        guard let link = block.link(.createBelow) else { return nil }
        do {
            let created: Block = try await app.client.fetch(
                from: link, method: "POST",
                body: CreateBlockBelowCommand(content: content, personId: nil, type: type.rawValue))
            await loadBlocks()
            await refreshUndoRedo()
            errorMessage = nil
            return created
        } catch {
            report(error)
            return nil
        }
    }

    /// The first element of an empty script: there is nothing to insert below
    /// yet, so the server mints the blank block for us to type into.
    @discardableResult
    func createFirstBlock() async -> Block? {
        guard let link = blocksLinks[.createInitial] else { return nil }
        do {
            let created: Block = try await app.client.fetch(from: link, method: "POST")
            await loadBlocks()
            await refreshUndoRedo()
            errorMessage = nil
            return created
        } catch {
            report(error)
            return nil
        }
    }

    /// Retypes a block — the element-type bar and Tab both land here. `content`
    /// carries the text currently on screen so an unsaved edit is not lost when
    /// the type changes.
    @discardableResult
    func setType(_ block: Block, to type: BlockType, content: String? = nil) async -> Bool {
        guard let link = block.link(.setType) else { return false }
        do {
            let updated: Block = try await app.client.fetch(
                from: link, method: "POST",
                body: SetBlockTypeCommand(type: type.rawValue,
                                          content: content,
                                          personId: block.personId,
                                          tags: nil))
            replace(updated)
            // Retyping a cue can mint a character, and DIALOGUE after a cue
            // rewrites content server-side, so take the server's word for both.
            await loadBlocks()
            await loadCharacters()
            await refreshUndoRedo()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Drag-to-reorder. Offsets are positions in `blocks`; the server wants the
    /// absolute order the block should take.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) async {
        guard let sourceIndex = source.first, blocks.indices.contains(sourceIndex) else { return }
        let block = blocks[sourceIndex]
        guard let link = block.link(.move) else { return }

        // SwiftUI hands back the destination as an index into the list *before*
        // the row is lifted out, so dragging downward overshoots by one.
        var reordered = blocks
        reordered.remove(at: sourceIndex)
        let finalIndex = destination > sourceIndex ? destination - 1 : destination
        guard finalIndex != sourceIndex, reordered.indices.contains(finalIndex)
                || finalIndex == reordered.count
        else { return }
        reordered.insert(block, at: finalIndex)

        // Orders are contiguous but not assumed to start at any given number:
        // the block lands on whichever order now sits at that position.
        let orders = blocks.compactMap(\.order).sorted()
        guard orders.indices.contains(finalIndex) else { return }

        blocks = reordered   // move now; the reload below confirms it
        do {
            let _: Block = try await app.client.fetch(
                from: link, method: "POST",
                body: MoveBlockCommand(position: orders[finalIndex]))
            await loadBlocks()
            await refreshUndoRedo()
            errorMessage = nil
        } catch {
            await loadBlocks()   // put it back where the server says it is
            report(error)
        }
    }

    func toggleBookmark(_ block: Block) async {
        await toggle(block, rel: .toggleBookmark)
    }

    func togglePinned(_ block: Block) async {
        await toggle(block, rel: .togglePinned)
    }

    private func toggle(_ block: Block, rel: Rel) async {
        guard let link = block.link(rel) else { return }
        do {
            let updated: Block = try await app.client.fetch(from: link, method: "POST")
            replace(updated)
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    private func replace(_ updated: Block) {
        if let index = blocks.firstIndex(where: { $0.id == updated.id }) {
            blocks[index] = updated
        }
    }

    // MARK: - Undo / redo

    func refreshUndoRedo() async {
        guard let link = project.link(.undoRedoStatus) else { return }
        do {
            undoRedo = try await app.client.fetch(UndoRedoStatus.self, from: link)
        } catch {
            // Non-critical; leave stale status rather than surfacing an alert.
        }
    }

    func undo() async {
        await performUndoRedo(rel: .undo)
    }

    func redo() async {
        await performUndoRedo(rel: .redo)
    }

    private func performUndoRedo(rel: Rel) async {
        guard let link = undoRedo?.link(rel) else { return }
        do {
            undoRedo = try await app.client.fetch(UndoRedoStatus.self, from: link, method: "POST")
            await loadBlocks()
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    // MARK: - Sync polling

    func startSyncPolling() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.syncInterval)
                guard !Task.isCancelled else { return }
                await self?.pollSync()
            }
        }
    }

    func stopSyncPolling() {
        syncTask?.cancel()
        syncTask = nil
    }

    private func pollSync() async {
        guard !hasActiveEdit, let base = project.link(.syncStatus) else { return }
        let link = base.addingQuery(["since": String(lastRevision)])
        do {
            let status: SyncStatus = try await app.client.fetch(from: link)
            guard status.exists ?? true else { return }
            let revision = status.revision ?? lastRevision
            if lastRevision == 0 {
                // First poll establishes the baseline; the blocks were just loaded.
                lastRevision = revision
                return
            }
            if (status.changed ?? false) && revision != lastRevision {
                lastRevision = revision
                await loadBlocks()
                await refreshUndoRedo()
            }
        } catch {
            // Transient polling errors are ignored; the next tick retries.
        }
    }

    private func report(_ error: Error) {
        app.handle(error)
        errorMessage = error.localizedDescription
    }

    // MARK: - Characters

    @discardableResult
    func createCharacter(name: String, fullName: String) async -> Bool {
        guard let link = charactersLinks[.selfRel] ?? project.link(.characters) else { return false }
        do {
            let _: Person = try await app.client.fetch(
                from: link, method: "POST",
                body: CreatePersonCommand(name: name, fullName: fullName,
                                          actorId: nil, projectId: project.id))
            await loadCharacters()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    @discardableResult
    func updateCharacter(_ person: Person, name: String, fullName: String) async -> Bool {
        guard let link = person.link(.update) else { return false }
        do {
            let _: Person = try await app.client.fetch(
                from: link, method: "PUT",
                body: EditPersonCommand(name: name, fullName: fullName,
                                        actorId: person.actorId, projectId: person.projectId))
            await loadCharacters()
            await loadBlocks()   // dialogue rows show personName
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    func deleteCharacter(_ person: Person) async {
        guard let link = person.link(.delete) else { return }
        do {
            try await app.client.data(for: link, method: "DELETE")
            characters.removeAll { $0.id == person.id }
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    // MARK: - Export

    struct ExportOption: Identifiable {
        let rel: Rel
        let label: String
        let fileExtension: String
        let link: HALLink

        var id: String { rel.rawValue }
    }

    var exportOptions: [ExportOption] {
        let all: [(Rel, String, String)] = [
            (.exportPdf, "PDF", "pdf"),
            (.export, "Fountain", "fountain"),
            (.exportDocx, "Word", "docx"),
            (.exportFdx, "Final Draft", "fdx"),
        ]
        return all.compactMap { rel, label, ext in
            project.link(rel).map { ExportOption(rel: rel, label: label, fileExtension: ext, link: $0) }
        }
    }

    /// Downloads an export with auth and writes it to a shareable temp file.
    func export(_ option: ExportOption) async throws -> URL {
        let data = try await app.client.data(for: option.link)
        let safeTitle = project.displayTitle
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined()
        let name = (safeTitle.isEmpty ? "script" : safeTitle) + "." + option.fileExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
