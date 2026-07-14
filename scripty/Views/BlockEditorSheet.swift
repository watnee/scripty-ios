//
//  BlockEditorSheet.swift
//  scripty
//
//  Everything about an element except its text: which type it is, who speaks it,
//  its tags, and whether it is pinned or bookmarked. The text itself is typed
//  straight into the page — see BlockEditorRow.
//

import SwiftUI

struct BlockEditorSheet: View {
    let model: ScriptModel
    let block: Block

    @Environment(\.dismiss) private var dismiss
    @State private var type: BlockType
    @State private var personId: Int?
    @State private var tags: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(model: ScriptModel, block: Block) {
        self.model = model
        self.block = block
        _type = State(initialValue: block.blockType)
        _personId = State(initialValue: block.personId)
        _tags = State(initialValue: block.tags ?? "")
    }

    private var canRetype: Bool { block.hasLink(.setType) }

    private var showsCharacterPicker: Bool {
        (type == .dialogue || type.isCharacterCue) && !model.characters.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if canRetype {
                        Picker("Type", selection: $type) {
                            ForEach(BlockType.allCases) { candidate in
                                Text(candidate.label).tag(candidate)
                            }
                        }
                    } else {
                        LabeledContent("Type", value: type.label)
                    }

                    if showsCharacterPicker {
                        Picker("Character", selection: $personId) {
                            Text("None").tag(Int?.none)
                            ForEach(model.characters) { person in
                                Text(person.displayName).tag(Int?.some(person.id))
                            }
                        }
                    }
                }

                Section("Tags") {
                    TextField("Comma-separated tags", text: $tags)
                        .textInputAutocapitalization(.never)
                }

                togglesSection

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Element")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var togglesSection: some View {
        let canBookmark = block.hasLink(.toggleBookmark)
        let canPin = block.hasLink(.togglePinned)
        if canBookmark || canPin {
            Section {
                if canBookmark {
                    Button {
                        Task { await model.toggleBookmark(block) }
                        dismiss()
                    } label: {
                        Label(block.isBookmarked ? "Remove Bookmark" : "Bookmark",
                              systemImage: block.isBookmarked ? "bookmark.slash" : "bookmark")
                    }
                }
                if canPin {
                    Button {
                        Task { await model.togglePinned(block) }
                        dismiss()
                    } label: {
                        Label(block.isPinned ? "Unpin" : "Pin",
                              systemImage: block.isPinned ? "pin.slash" : "pin")
                    }
                }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let trimmedTags = tags.trimmingCharacters(in: .whitespaces)

        Task {
            var succeeded = true
            if type != block.blockType, canRetype {
                succeeded = await model.setType(block, to: type, content: block.content)
            }
            if succeeded, block.hasLink(.update) {
                succeeded = await model.updateBlock(
                    block,
                    content: block.content ?? "",
                    personId: showsCharacterPicker ? personId : block.personId,
                    tags: trimmedTags.isEmpty ? nil : trimmedTags)
            }

            isSaving = false
            if succeeded {
                dismiss()
            } else {
                errorMessage = model.errorMessage
            }
        }
    }
}
