//
//  ScriptSearchBar.swift
//  scripty
//
//  Find-in-script, presented as a bar above the keyboard rather than the web
//  app's filtering dropdown: type, watch the "n of m" counter, and step
//  through the hits with the chevrons. Each step scrolls the script page.
//

import SwiftUI

struct ScriptSearchBar: View {
    let model: ScriptModel
    let navigator: ScriptNavigator
    @Bindable var search: ScriptSearchModel
    /// Called when the writer taps Done; the host hides the bar.
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                field

                Text(search.statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60, alignment: .trailing)
                    .animation(nil, value: search.statusText)

                Button {
                    jump(search.previous())
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!search.hasMatches)

                Button {
                    jump(search.next())
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(!search.hasMatches)

                Button("Done") {
                    search.clear()
                    isFocused = false
                    onDismiss()
                }
                .font(.body.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .onAppear { isFocused = true }
        .onChange(of: search.query) { _, _ in
            search.refresh(in: model.blocks)
            // Land on the first hit as soon as the query resolves to one.
            if let match = search.current { navigator.jump(to: match.blockId) }
        }
        .onChange(of: model.blocks) { _, blocks in
            // A sync refresh or an edit can move the hits underneath us.
            search.refresh(in: blocks)
        }
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search script, characters, tags", text: $search.query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.next)
                .focused($isFocused)
                .onSubmit { jump(search.next()) }
            if search.hasQuery {
                Button {
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func jump(_ match: ScriptSearchModel.Match?) {
        guard let match else { return }
        navigator.jump(to: match.blockId)
    }
}
