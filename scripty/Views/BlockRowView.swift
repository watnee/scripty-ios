//
//  BlockRowView.swift
//  scripty
//
//  A screenplay element rendered read-only — used for scripts the reader cannot
//  edit, and for page breaks, which hold no text. Editable elements are typed
//  into directly; see BlockEditorRow. Both draw on BlockStyle, so a block sits in
//  the same place on the page either way.
//

import SwiftUI

struct BlockRowView: View {
    let block: Block

    private var style: BlockStyle {
        BlockStyle.of(block.blockType).applying(block)
    }

    var body: some View {
        element
            .frame(maxWidth: style.columnWidth ?? .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: style.columnAlignment)
            .padding(.top, style.topPadding)
            .overlay(alignment: .topTrailing) { badges }
    }

    @ViewBuilder
    private var element: some View {
        switch block.blockType {
        case .pageBreak:
            HStack(spacing: 12) {
                rule
                Text("PAGE BREAK")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                rule
            }
            .padding(.vertical, 8)

        case .note:
            text
                .padding(8)
                .background(Color.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))

        default:
            text
        }
    }

    private var text: some View {
        styledText
            .font(style.font(for: block))
            .italic(style.italic)
            .foregroundStyle(style.secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .multilineTextAlignment(style.textAlignment)
            .frame(maxWidth: .infinity, alignment: style.columnAlignment)
    }

    private var styledText: Text {
        var rendered = Text(displayContent.isEmpty ? " " : displayContent)
        if block.textUnderline ?? false { rendered = rendered.underline() }
        return rendered
    }

    private var rule: some View {
        Rectangle()
            .fill(.tertiary)
            .frame(height: 1)
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

    /// Scene headings and cues read as uppercase on the page, and parentheticals
    /// wear their brackets. The stored text is left untouched, as on the web.
    private var displayContent: String {
        var content = block.content ?? ""
        if content.isEmpty, block.blockType.isCharacterCue, let name = block.personName {
            content = name
        }
        if block.blockType == .parenthetical, !content.isEmpty, !content.hasPrefix("(") {
            return "(\(content))"
        }
        return style.uppercase ? content.uppercased() : content
    }
}
