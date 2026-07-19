//
//  CommentsView.swift
//  scripty
//
//  The comment thread on one screenplay element, with the element itself at the
//  top so the note has something to be about.
//
//  Commenting needs only read access — it is how a director or producer
//  contributes to a script they may not edit — so the composer appears wherever
//  the server offered it, including for readers who see no editing controls at
//  all.
//

import SwiftUI

struct CommentsView: View {
    let block: Block
    @State private var model: CommentsModel

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var pendingDelete: BlockComment?
    @FocusState private var composerFocused: Bool

    init(app: AppModel, block: Block, source: HALLink) {
        self.block = block
        _model = State(initialValue: CommentsModel(app: app, source: source))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                excerpt
                Divider()
                thread
                if model.canComment {
                    Divider()
                    composer
                }
            }
            .navigationTitle("Comments")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await model.load() }
            .alert("Delete Comment", isPresented: deleteBinding) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    let comment = pendingDelete
                    pendingDelete = nil
                    Task {
                        guard let comment else { return }
                        await model.delete(comment)
                    }
                }
            } message: {
                Text("This cannot be undone.")
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    /// The element being discussed, so the thread is not floating free.
    private var excerpt: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(block.blockType.label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(excerptText)
                .font(.callout)
                .lineLimit(3)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.25))
    }

    private var excerptText: String {
        let content = (block.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty, block.blockType.isCharacterCue, let name = block.personName {
            return name
        }
        return content.isEmpty ? "Empty element" : content
    }

    @ViewBuilder
    private var thread: some View {
        if model.isEmpty {
            Spacer(minLength: 0)
            if model.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView(
                    "No Comments",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(model.canComment
                                      ? "Start the discussion on this element."
                                      : "Nobody has commented on this element."))
            }
            Spacer(minLength: 0)
        } else {
            List {
                ForEach(model.comments) { comment in
                    row(comment)
                }
            }
            .listStyle(.plain)
        }
    }

    private func row(_ comment: BlockComment) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(comment.displayAuthor)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let created = comment.createdAt {
                    Text(created, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(comment.displayBody)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            // The server decides who may remove a comment; it says so by
            // offering the link.
            if comment.canDelete {
                Button(role: .destructive) {
                    pendingDelete = comment
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Add a comment", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                .focused($composerFocused)

            Button {
                let body = draft
                draft = ""
                composerFocused = false
                Task { await model.add(body) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || model.isWorking)
            .accessibilityLabel("Post Comment")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}
