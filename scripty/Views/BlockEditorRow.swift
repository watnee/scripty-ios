//
//  BlockEditorRow.swift
//  scripty
//
//  One screenplay element, edited in place. Typing goes straight into the page
//  the way it does in the web editor: Return opens the next element, Tab cycles
//  this one's type, and the text keeps its screenplay typography throughout.
//

import SwiftUI

struct BlockEditorRow: View {
    let block: Block
    @Binding var text: String
    @FocusState.Binding var focusedBlock: Int?

    /// Return was pressed: the text before the caret stays here, the text after
    /// it moves into a new element below.
    let onReturn: (_ before: String, _ after: String) -> Void
    /// Tab (or Shift-Tab, when `backward`) — retype this element.
    let onCycleType: (_ backward: Bool) -> Void

    private var style: BlockStyle {
        BlockStyle.of(block.blockType).applying(block)
    }

    var body: some View {
        field
            .frame(maxWidth: style.columnWidth ?? .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: style.columnAlignment)
            .padding(.top, style.topPadding)
            .overlay(alignment: .topTrailing) { badges }
    }

    private var field: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(style.font(for: block))
            .italic(style.italic)
            .underline(block.textUnderline ?? false)
            .foregroundStyle(style.secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .multilineTextAlignment(style.textAlignment)
            .textInputAutocapitalization(block.blockType.isUppercase ? .characters : .sentences)
            .autocorrectionDisabled(block.blockType.isUppercase)
            .focused($focusedBlock, equals: block.id)
            .noteBackground(block.blockType == .note)
            .onChange(of: text) { _, newValue in
                handleTyping(newValue)
            }
            .onKeyPress(keys: [.tab]) { press in
                onCycleType(press.modifiers.contains(.shift))
                return .handled
            }
    }

    /// A newline only ever arrives here by pressing Return (or pasting), and the
    /// page has no room for one inside a single element — so treat it as the
    /// break between this element and the next.
    private func handleTyping(_ newValue: String) {
        guard let newline = newValue.firstRange(of: "\n") else { return }
        let before = String(newValue[..<newline.lowerBound])
        let after = String(newValue[newline.upperBound...])
        text = before
        onReturn(before, after)
    }

    private var placeholder: String {
        switch block.blockType {
        case .scene: return "INT. LOCATION - DAY"
        case .character, .dualDialogue: return "CHARACTER"
        case .parenthetical: return "(beat)"
        case .transition: return "CUT TO:"
        default: return block.blockType.label
        }
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 4) {
            if block.isPinned {
                Image(systemName: "pin.fill")
            }
            if block.isBookmarked {
                Image(systemName: "bookmark.fill")
            }
        }
        .font(.caption2)
        .foregroundStyle(.orange)
    }
}

private extension View {
    /// Notes sit on the page as a tinted card, as they do on the web.
    @ViewBuilder
    func noteBackground(_ isNote: Bool) -> some View {
        if isNote {
            padding(8)
                .background(Color.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
        } else {
            self
        }
    }
}
