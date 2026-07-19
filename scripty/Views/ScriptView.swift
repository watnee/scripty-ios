//
//  ScriptView.swift
//  scripty
//
//  The screenplay page for one project. Editable elements are typed into
//  directly — Return, Backspace and Tab split, merge and retype the way the
//  web editor does — so writing is continuous rather than one block at a
//  time. Every affordance is still gated by the links the server advertised.
//

import SwiftUI

struct ScriptView: View {
    @State private var model: ScriptModel
    @State private var showingCharacters = false
    @State private var showingSongs = false
    @State private var showingTitlePage = false
    @State private var showingOutline = false
    @State private var showingStats = false
    @State private var isSearching = false
    @State private var navigator = ScriptNavigator()
    @State private var search = ScriptSearchModel()

    init(app: AppModel, project: Project) {
        _model = State(initialValue: ScriptModel(app: app, project: project))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.blocks) { block in
                        row(for: block)
                            .padding(.horizontal, 24)
                            .id(block.id)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: navigator.pendingScrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
                // Clearing the target is what lets the same block be jumped
                // to twice in a row.
                navigator.consumeScrollTarget()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay { emptyState }
        .safeAreaInset(edge: .bottom) { editingBars }
        .safeAreaInset(edge: .bottom) { searchBar }
        .navigationTitle(model.project.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .refreshable {
            await model.loadBlocks()
            await model.refreshUndoRedo()
        }
        .task {
            await model.loadEverything()
            model.startSyncPolling()
        }
        .onDisappear { model.stopSyncPolling() }
        .sheet(isPresented: $showingCharacters) {
            CharactersView(model: model)
        }
        .sheet(isPresented: $showingSongs) {
            SongsView(model: model)
        }
        .sheet(isPresented: $showingTitlePage) {
            TitlePageView(app: model.app, project: model.project) { updated in
                model.adopt(updated)
            }
        }
        .sheet(isPresented: $showingOutline) {
            ScriptOutlineView(model: model, navigator: navigator)
        }
        .sheet(isPresented: $showingStats) {
            ScriptStatsView(model: model)
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func row(for block: Block) -> some View {
        if block.isEditable {
            EditableBlockRow(model: model, block: block)
        } else {
            BlockRowView(block: block)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.blocks.isEmpty {
            if model.isLoading {
                ProgressView()
            } else if model.canSeedScript {
                ContentUnavailableView {
                    Label("Empty Script", systemImage: "doc.plaintext")
                } description: {
                    Text("Start writing to add the first element.")
                } actions: {
                    Button("Start Writing") {
                        Task { await model.seedInitialBlock() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView(
                    "Empty Script",
                    systemImage: "doc.plaintext",
                    description: Text("This script has no elements yet."))
            }
        }
    }

    /// Formatting sits above the element-type bar, both only while a block is
    /// focused and only for the affordances the server actually advertised.
    @ViewBuilder
    private var editingBars: some View {
        if let id = model.focusedBlockId,
           let block = model.blocks.first(where: { $0.id == id }) {
            VStack(spacing: 0) {
                if block.hasLink(.update) {
                    FormatBar(model: model, block: block)
                    Divider()
                }
                if block.hasLink(.setType) {
                    ElementTypeBar(model: model, block: block)
                }
            }
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        if isSearching {
            ScriptSearchBar(model: model, navigator: navigator, search: search) {
                isSearching = false
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await model.appendBlock() }
            } label: {
                Label("Add Element", systemImage: "plus")
            }

            if model.hasScriptContent {
                Button {
                    isSearching.toggle()
                    if !isSearching { search.clear() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)

                Button {
                    showingOutline = true
                } label: {
                    Label("Outline", systemImage: "list.bullet.indent")
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            if model.canViewCharacters {
                Button {
                    showingCharacters = true
                } label: {
                    Label("Characters", systemImage: "person.2")
                }
            }

            if model.canViewDocuments {
                Button {
                    showingSongs = true
                } label: {
                    Label("Songs & Notes", systemImage: "music.note.list")
                }
            }

            if !model.exportOptions.isEmpty {
                ExportButton(model: model)
            }
        }

        // Front matter, import and stats are occasional actions — they live in
        // the overflow so the writing controls stay reachable on iPhone width.
        ToolbarItemGroup(placement: .secondaryAction) {
            Button {
                showingTitlePage = true
            } label: {
                Label("Title Page", systemImage: "doc.text")
            }

            if model.hasScriptContent {
                Button {
                    showingStats = true
                } label: {
                    Label("Script Stats", systemImage: "chart.bar")
                }
            }

            ScriptImportButton(app: model.app, project: model.project) { updated in
                model.adopt(updated)
                await model.loadBlocks()
                await model.refreshUndoRedo()
            }
        }

        if let undoRedo = model.undoRedo {
            ToolbarItemGroup(placement: .secondaryAction) {
                Button {
                    Task { await model.undo() }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!(undoRedo.canUndo ?? false))

                Button {
                    Task { await model.redo() }
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!(undoRedo.canRedo ?? false))
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } })
    }
}
