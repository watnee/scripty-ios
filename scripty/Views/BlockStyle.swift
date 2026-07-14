//
//  BlockStyle.swift
//  scripty
//
//  Screenplay typography for one element type. Shared by the editable row and
//  the read-only render so a block does not shift on the page when the caret
//  enters it.
//

import SwiftUI

struct BlockStyle {
    /// Width of the element's column. Nil means the full page width.
    var columnWidth: CGFloat?
    /// Where that column sits on the page.
    var columnAlignment: Alignment = .leading
    /// How the text flows inside the column.
    var textAlignment: TextAlignment = .leading
    var weight: Font.Weight = .regular
    var italic = false
    var secondary = false
    var topPadding: CGFloat = 0
    /// Titles that read as uppercase on the page (scene headings, cues, …).
    var uppercase = false

    static let pageWidth: CGFloat = 640
    private static let dialogueWidth: CGFloat = 400
    private static let parentheticalWidth: CGFloat = 320

    static func of(_ type: BlockType) -> BlockStyle {
        switch type {
        case .scene:
            return BlockStyle(columnWidth: nil, weight: .bold, topPadding: 18, uppercase: true)

        case .character, .dualDialogue:
            return BlockStyle(columnWidth: nil, columnAlignment: .center, textAlignment: .center,
                              topPadding: 10, uppercase: true)

        case .dialogue:
            return BlockStyle(columnWidth: dialogueWidth, columnAlignment: .center)

        case .parenthetical:
            return BlockStyle(columnWidth: parentheticalWidth, columnAlignment: .center, italic: true)

        case .transition:
            return BlockStyle(columnWidth: nil, columnAlignment: .trailing, textAlignment: .trailing,
                              topPadding: 10, uppercase: true)

        case .shot:
            return BlockStyle(columnWidth: nil, weight: .semibold, topPadding: 10, uppercase: true)

        case .centered:
            return BlockStyle(columnWidth: nil, columnAlignment: .center, textAlignment: .center)

        case .lyrics:
            return BlockStyle(columnWidth: dialogueWidth, columnAlignment: .center, italic: true)

        case .section:
            return BlockStyle(columnWidth: nil, weight: .semibold, secondary: true, topPadding: 14)

        case .synopsis:
            return BlockStyle(columnWidth: nil, italic: true, secondary: true)

        case .note, .action, .text, .pageBreak:
            return BlockStyle(columnWidth: nil)
        }
    }

    /// The block's own overrides (alignment, font, weight) win over the defaults
    /// for its type, matching how the web app treats per-block formatting.
    func applying(_ block: Block) -> BlockStyle {
        var style = self
        switch block.textAlign {
        case "CENTER":
            style.columnAlignment = .center
            style.textAlignment = .center
        case "RIGHT":
            style.columnAlignment = .trailing
            style.textAlignment = .trailing
        default:
            break
        }
        if block.textBold ?? false { style.weight = .bold }
        if block.textItalic ?? false { style.italic = true }
        return style
    }

    /// Screenplay convention is Courier; the server can override per block.
    func font(for block: Block) -> Font {
        let size: CGFloat = block.blockType == .section ? 20 : 16
        switch block.font {
        case "ARIAL", "TIMES_NEW_ROMAN":
            return .system(size: size, weight: weight)
        default:
            return .system(size: size, weight: weight, design: .monospaced)
        }
    }
}
