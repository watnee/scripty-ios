//
//  Block.swift
//  scripty
//

import Foundation

/// One screenplay element (a Fountain block): scene heading, action,
/// dialogue, transition, etc. Ordered by `order` within a project.
struct Block: Decodable, Identifiable, Hashable, HALResource {
    let id: Int
    var projectId: Int?
    var order: Int?
    var content: String?
    var type: String?
    var personId: Int?
    var personName: String?
    var bookmarked: Bool?
    var pinned: Bool?
    var scene: Bool?
    var tags: String?
    var textAlign: String?
    var font: String?
    var textBold: Bool?
    var textItalic: Bool?
    var textUnderline: Bool?
    let links: HALLinks?

    private enum CodingKeys: String, CodingKey {
        case id, projectId, order, content, type, personId, personName
        case bookmarked, pinned, scene, tags, textAlign, font
        case textBold, textItalic, textUnderline
        case links = "_links"
    }

    /// Unknown server types fall back to `.action` for rendering.
    var blockType: BlockType {
        BlockType(rawValue: type ?? "") ?? .action
    }

    var isBookmarked: Bool { bookmarked ?? false }
    var isPinned: Bool { pinned ?? false }

    /// True when the server advertises any mutation link for this block.
    var isEditable: Bool { hasLink(.update) }
}

/// Fountain screenplay element types (mirrors Block.java on the server).
enum BlockType: String, CaseIterable, Identifiable {
    case scene = "SCENE"
    case action = "ACTION"
    case text = "TEXT"
    case character = "CHARACTER"
    case dialogue = "DIALOGUE"
    case dualDialogue = "DUAL_DIALOGUE"
    case parenthetical = "PARENTHETICAL"
    case transition = "TRANSITION"
    case shot = "SHOT"
    case lyrics = "LYRICS"
    case centered = "CENTERED"
    case section = "SECTION"
    case synopsis = "SYNOPSIS"
    case note = "NOTE"
    case pageBreak = "PAGE_BREAK"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scene: return "Scene"
        case .action: return "Action"
        case .text: return "Text"
        case .character: return "Character"
        case .dialogue: return "Dialogue"
        case .dualDialogue: return "Dual Dialogue"
        case .parenthetical: return "Parenthetical"
        case .transition: return "Transition"
        case .shot: return "Shot"
        case .lyrics: return "Lyrics"
        case .centered: return "Centered"
        case .section: return "Section"
        case .synopsis: return "Synopsis"
        case .note: return "Note"
        case .pageBreak: return "Page Break"
        }
    }

    /// Character cues carry the speaker name as their content.
    var isCharacterCue: Bool {
        self == .character || self == .dualDialogue
    }

    /// Types that read as uppercase on the page, so the keyboard should start
    /// there. The stored text is left alone, exactly as the web app leaves it.
    var isUppercase: Bool {
        self == .scene || self == .transition || self == .shot || isCharacterCue
    }

    /// Blocks whose content the writer types. A page break has none.
    var isTextual: Bool {
        self != .pageBreak
    }

    // MARK: - Element flow (mirrors fountain-power.js)

    /// What Return opens next: a character cue is followed by their dialogue,
    /// and anything else by action.
    var nextOnEnter: BlockType {
        isCharacterCue ? .dialogue : .action
    }

    /// The classic Final Draft Tab order.
    static let tabCycle: [BlockType] = [
        .scene, .action, .character, .parenthetical, .dialogue, .transition, .shot,
    ]

    /// Types outside the Tab order join it at their nearest equivalent, so Tab
    /// from a Note advances as though it were Action.
    private var tabCycleEntry: BlockType {
        switch self {
        case .text, .centered, .note: return .action
        case .lyrics: return .dialogue
        case .dualDialogue: return .character
        case .section, .synopsis, .pageBreak: return .scene
        default: return self
        }
    }

    /// The next element type when cycling with Tab (or the previous one with
    /// Shift-Tab), wrapping around the cycle.
    func cycled(backward: Bool = false) -> BlockType {
        let cycle = Self.tabCycle
        let index = cycle.firstIndex(of: tabCycleEntry) ?? 0
        let step = backward ? -1 : 1
        return cycle[(index + step + cycle.count) % cycle.count]
    }
}

struct CreateBlockCommand: Encodable {
    var content: String
    var personId: Int?
    var projectId: Int
    var type: String
}

/// Edits text and metadata. To change the element type, use `SetBlockTypeCommand`.
struct EditBlockCommand: Encodable {
    var content: String
    var personId: Int?
    var tags: String?
}

/// Inserts a block directly below another — what Return does in the editor.
/// Empty content is normal: the new element is blank until it is typed into.
struct CreateBlockBelowCommand: Encodable {
    var content: String
    var personId: Int?
    var type: String
}

/// Retypes a block. A nil `content` keeps the text the block already has.
struct SetBlockTypeCommand: Encodable {
    var type: String
    var content: String?
    var personId: Int?
    var tags: String?
}

/// Reorders a block to an absolute position in the script.
struct MoveBlockCommand: Encodable {
    var position: Int
}
