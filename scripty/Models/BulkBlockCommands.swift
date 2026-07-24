//
//  BulkBlockCommands.swift
//  scripty
//
//  Requests for the block collection's bulk operations. These act on a set of
//  blocks and land as one undo checkpoint on the server, which is the reason
//  they exist as endpoints rather than as a loop over the per-block calls —
//  retyping twenty elements should take one press of undo, not twenty.
//

import Foundation

/// Retype every selected element.
struct BulkSetTypeCommand: Encodable {
    var ids: [Int]
    var projectId: Int
    var type: String
}

/// Add tags to every selected element. Additive on the server: a tag already
/// present is not repeated, and the existing casing wins.
struct BulkAddTagsCommand: Encodable {
    var ids: [Int]
    var projectId: Int
    var tags: String
}

struct BulkDeleteCommand: Encodable {
    var ids: [Int]
    var projectId: Int
}

/// Alignment, font, a style toggle and a highlight in one call, so several
/// changes share a single checkpoint.
///
/// Every field is optional and omitted fields are left alone — which is why
/// clearing a highlight or resetting a font needs its own flag rather than a
/// nil/blank value, since nil already means "leave it" and the server rejects a
/// blank font outright.
struct BulkFormatCommand: Encodable {
    var ids: [Int]
    var projectId: Int
    var align: String?
    var font: String?
    /// A per-block *toggle*: a mixed selection comes back inverted, not
    /// uniform. That is the web behaviour, preserved deliberately.
    var style: String?
    var highlight: String?
    var clearHighlight: Bool?
    /// Reset the font to the default. A blank `font` cannot mean this, because
    /// the server rejects any font it does not recognise; the flag is the
    /// counterpart of `clearHighlight`.
    var clearFont: Bool?
}

/// Find and replace across the selected elements. `find` is matched literally,
/// never as a regular expression.
struct BulkReplaceCommand: Encodable {
    var ids: [Int]
    var projectId: Int
    var find: String
    var replace: String
    var matchCase: Bool
    var wholeWord: Bool
    /// Character cues mirror their person record, so they are left out unless
    /// the writer opts in.
    var includeCharacterCues: Bool
}

/// The background tints a block can carry (mirrors `Block.HIGHLIGHTS`).
enum BlockHighlight: String, CaseIterable, Identifiable {
    case yellow = "YELLOW"
    case green = "GREEN"
    case blue = "BLUE"
    case red = "RED"
    case gray = "GRAY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .red: return "Red"
        case .gray: return "Grey"
        }
    }

    /// The server stores an uppercase key and clears the tint on anything it
    /// does not recognise, so decoding is deliberately lenient.
    init?(serverValue: String?) {
        guard let raw = serverValue?.trimmingCharacters(in: .whitespaces).uppercased(),
              !raw.isEmpty,
              let value = BlockHighlight(rawValue: raw) else { return nil }
        self = value
    }
}

/// The three character styles the format bar toggles (mirrors
/// `Block.TEXT_STYLES`).
enum BlockTextStyle: String, CaseIterable, Identifiable {
    case bold = "BOLD"
    case italic = "ITALIC"
    case underline = "UNDERLINE"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .underline: return "underline"
        }
    }
}
