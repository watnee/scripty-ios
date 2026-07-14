//
//  ScriptView.swift
//  scripty
//
//  The screenplay page for one project, edited in place like the web app:
//  tap anywhere and type, Return opens the next element, the bar above the
//  keyboard retypes the current one, and blocks drag to reorder. Every
//  affordance is still gated by the links the server advertised.
//

import SwiftUI

struct ScriptView: View {
    @State private var model: ScriptModel
    @State private var showingCharacters = false
    @State private var detailBlock: Block?

    /// Which element holds the caret. Nil means the keyboard is down.
    @FocusState private var focusedBlock: Int?
    /// In-progress text per block, held until the row loses focus.
    @State private var drafts: [Int: String] = [:]

    init(app: AppModel, project: Project) {
        _model = State(initialValue: ScriptModel(app: app, project: project))
    }

    private var focused: Block? {
        model.blocks.first { $0.id == focusedBlock }
    }

    var body: some View {
        List {
            ForEach(model.blocks) { block in
                row(for: block)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 24, bottom: 2, trailing: 24))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        swipeActions(for: block)
                    }
                    .contextMenu {
                        contextMenu(for: block)
                    }
            }
            .onMove { source, destination in
                Task { await model.move(fromOffsets: source, toOffset: destination) }
            }
        }
        .listStyle(.plain)
        .overlay { emptyState }
        .navigationTitle(model.project.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .toolbar { keyboardBar }
        .refreshable {
            await model.loadBlocks()
            await model.refreshUndoRedo()
        }
        .task {
            await model.loadEverything()
            model.startSyncPolling()
        }
        .onDisappear {
            commitDraft(for: focusedBlock)
            model.stopSyncPolling()
        }
        .onChange(of: focusedBlock) { previous, current in
            // Leaving a row saves it; a row with the caret in it pauses the sync
            // poller so a refresh cannot overwrite what is being typed.
            commitDraft(for: previous)
            model.hasActiveEdit = current != nil
        }
        .sheet(isPresented: $showingCharacters) {
            CharactersView(model: model)
        }
        .sheet(item: $detailBlock) { block in
            BlockEditorSheet(model: model, block: block)
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for block: Block) -> some View {
        if block.isEditable, block.blockType.isTextual {
            BlockEditorRow(
                block: block,
                text: draft(for: block),
                focusedBlock: $focusedBlock,
                onReturn: { before, after in
                    handleReturn(block, before: before, after: after)
                },
                onCycleType: { backward in
                    apply(block.blockType.cycled(backward: backward), to: block)
                })
        } else {
            // Read-only scripts, and page breaks, which hold no text.
            BlockRowView(block: block)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func swipeActions(for block: Block) -> some View {
        if block.hasLink(.delete) {
            Button(role: .destructive) {
                Task { await model.deleteBlock(block) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        if block.hasLink(.toggleBookmark) {
            Button {
                Task { await model.toggleBookmark(block) }
            } label: {
                Label("Bookmark", systemImage: "bookmark")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func contextMenu(for block: Block) -> some View {
        if block.hasLink(.createBelow) {
            Button {
                insertBelow(block)
            } label: {
                Label("Insert Below", systemImage: "text.insert")
            }
        }
        if block.hasLink(.togglePinned) {
            Button {
                Task { await model.togglePinned(block) }
            } label: {
                Label(block.isPinned ? "Unpin" : "Pin",
                      systemImage: block.isPinned ? "pin.slash" : "pin")
            }
        }
        if block.isEditable {
            Button {
                detailBlock = block
            } label: {
                Label("Tags & Details", systemImage: "tag")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.blocks.isEmpty {
            if model.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView {
                    Label("Empty Script", systemImage: "doc.plaintext")
                } description: {
                    Text("Start writing, and press return for each new element.")
                } actions: {
                    if model.canStartScript {
                        Button("Start Writing") {
                            Task {
                                if let first = await model.createFirstBlock() {
                                    focusedBlock = first.id
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.canViewCharacters {
                Button {
                    showingCharacters = true
                } label: {
                    Label("Characters", systemImage: "person.2")
                }
            }

            if !model.exportOptions.isEmpty {
                ExportButton(model: model)
            }
        }

        if let undoRedo = model.undoRedo {
            ToolbarItemGroup(placement: .secondaryAction) {
                Button {
                    endEditing()
                    Task { await model.undo() }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!(undoRedo.canUndo ?? false))

                Button {
                    endEditing()
                    Task { await model.redo() }
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!(undoRedo.canRedo ?? false))
            }
        }
    }

    /// The element bar rides above the keyboard, so retyping the element you are
    /// in never means putting the keyboard away.
    @ToolbarContentBuilder
    private var keyboardBar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            if let block = focused {
                ElementTypeBar(
                    block: block,
                    characters: model.characters,
                    onSelect: { apply($0, to: block) },
                    onPickCharacter: { pickCharacter($0, for: block) },
                    onDone: { endEditing() })
            }
        }
    }

    // MARK: - Editing

    /// The row's text: whatever is being typed, or what the server last stored.
    private func draft(for block: Block) -> Binding<String> {
        Binding(
            get: { drafts[block.id] ?? block.content ?? "" },
            set: { drafts[block.id] = $0 })
    }

    /// Saves a row's pending text. Cheap to call: it no-ops when nothing changed.
    private func commitDraft(for id: Int?) {
        guard let id, let text = drafts[id],
              let block = model.blocks.first(where: { $0.id == id })
        else { return }
        drafts[id] = nil
        guard text != (block.content ?? "") else { return }
        Task { await model.commit(block, content: text) }
    }

    /// Return: keep `before` here, carry `after` into a new element below, and
    /// follow the caret into it.
    private func handleReturn(_ block: Block, before: String, after: String) {
        drafts[block.id] = before
        Task {
            guard let created = await model.splitBlock(block, before: before, after: after) else { return }
            drafts[block.id] = nil     // the server holds `before` now
            focusedBlock = created.id
        }
    }

    private func insertBelow(_ block: Block) {
        Task {
            guard let created = await model.createBlockBelow(
                block, type: block.blockType.nextOnEnter) else { return }
            focusedBlock = created.id
        }
    }

    /// Retype the element, carrying any unsaved text along so it survives.
    private func apply(_ type: BlockType, to block: Block) {
        let pending = drafts[block.id]
        Task {
            await model.setType(block, to: type, content: pending)
            drafts[block.id] = nil     // the server's version wins from here
        }
    }

    /// A cue picked from the cast: name the speaker and link the character.
    private func pickCharacter(_ person: Person, for block: Block) {
        Task {
            await model.setType(block, to: block.blockType, content: person.displayName)
            drafts[block.id] = nil
        }
    }

    private func endEditing() {
        commitDraft(for: focusedBlock)
        focusedBlock = nil
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil && detailBlock == nil },
            set: { if !$0 { model.errorMessage = nil } })
    }
}
