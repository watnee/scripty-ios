//
//  ScriptSearchModel.swift
//  scripty
//
//  Find-in-script over the blocks we already hold. Matches the web app's
//  project search: a case-insensitive substring test against the element's
//  content, the speaking character's name, and its tags. Where the web filters
//  rows out, we walk the hits one at a time — the phone equivalent.
//

import Foundation
import Observation

@Observable @MainActor
final class ScriptSearchModel {

    /// Which part of the block the query was found in.
    enum Field {
        case content, character, tags

        var label: String {
            switch self {
            case .content: return "Text"
            case .character: return "Character"
            case .tags: return "Tag"
            }
        }
    }

    struct Match: Identifiable, Hashable {
        let blockId: Int
        let type: BlockType
        /// The hit shown in context, elided at both ends where text was cut.
        let snippet: String
        let field: Field

        var id: Int { blockId }

        static func == (lhs: Match, rhs: Match) -> Bool { lhs.blockId == rhs.blockId }
        func hash(into hasher: inout Hasher) { hasher.combine(blockId) }
    }

    /// What the writer typed. Call `refresh(in:)` after changing it.
    var query = ""

    private(set) var matches: [Match] = []
    /// Index into `matches`; meaningless while `matches` is empty.
    private(set) var currentIndex = 0

    /// Characters of surrounding text kept on either side of a hit.
    private static let snippetContext = 28

    var current: Match? {
        matches.indices.contains(currentIndex) ? matches[currentIndex] : nil
    }

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasMatches: Bool { !matches.isEmpty }

    /// The "3 of 12" readout next to the field.
    var statusText: String {
        guard hasQuery else { return "" }
        guard hasMatches else { return "No results" }
        return "\(currentIndex + 1) of \(matches.count)"
    }

    // MARK: - Searching

    /// Recompute the hit list. Keeps the caret on the same block when that
    /// block still matches, so typing another letter doesn't jump the reader
    /// back to the top.
    func refresh(in blocks: [Block]) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            matches = []
            currentIndex = 0
            return
        }

        let previous = current?.blockId
        matches = blocks.compactMap { Self.match($0, needle: needle) }
        if let previous, let index = matches.firstIndex(where: { $0.blockId == previous }) {
            currentIndex = index
        } else {
            currentIndex = 0
        }
    }

    func clear() {
        query = ""
        matches = []
        currentIndex = 0
    }

    // MARK: - Navigation

    /// Advance to the next hit, wrapping at the end.
    @discardableResult
    func next() -> Match? {
        guard !matches.isEmpty else { return nil }
        currentIndex = (currentIndex + 1) % matches.count
        return current
    }

    /// Step back to the previous hit, wrapping at the start.
    @discardableResult
    func previous() -> Match? {
        guard !matches.isEmpty else { return nil }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        return current
    }

    /// Jump straight to a known hit (tapping a row in a results list).
    @discardableResult
    func select(_ match: Match) -> Match? {
        guard let index = matches.firstIndex(where: { $0.blockId == match.blockId }) else { return nil }
        currentIndex = index
        return current
    }

    // MARK: - Matching

    private static func match(_ block: Block, needle: String) -> Match? {
        let content = block.content ?? ""
        if let snippet = snippet(content, needle: needle) {
            return Match(blockId: block.id, type: block.blockType, snippet: snippet, field: .content)
        }
        if let name = block.personName, name.lowercased().contains(needle) {
            return Match(blockId: block.id, type: block.blockType, snippet: name, field: .character)
        }
        if let tags = block.tags, tags.lowercased().contains(needle) {
            return Match(blockId: block.id, type: block.blockType, snippet: tags, field: .tags)
        }
        return nil
    }

    /// The first hit inside `text` with a little context either side, or nil
    /// when the needle isn't there.
    private static func snippet(_ text: String, needle: String) -> String? {
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        guard let hit = flattened.range(of: needle, options: .caseInsensitive) else { return nil }

        let start = flattened.index(hit.lowerBound, offsetBy: -snippetContext,
                                    limitedBy: flattened.startIndex) ?? flattened.startIndex
        let end = flattened.index(hit.upperBound, offsetBy: snippetContext,
                                  limitedBy: flattened.endIndex) ?? flattened.endIndex

        var snippet = String(flattened[start..<end]).trimmingCharacters(in: .whitespaces)
        if start != flattened.startIndex { snippet = "…" + snippet }
        if end != flattened.endIndex { snippet += "…" }
        return snippet
    }
}
