//
//  BlockComment.swift
//  scripty
//
//  A note left on a screenplay element.
//
//  Commenting is the one collaborative act that needs only read access — it is
//  how a director or a producer contributes to a script they may not edit — so
//  the affordance appears for readers too.
//

import Foundation

struct BlockComment: Decodable, Identifiable, Hashable, HALResource {
    let id: Int
    var blockId: Int?
    var authorId: Int?
    var authorName: String?
    var body: String?
    var createdAt: Date?
    let links: HALLinks?

    private enum CodingKeys: String, CodingKey {
        case id, blockId, authorId, authorName, body, createdAt
        case links = "_links"
    }

    var displayAuthor: String {
        let trimmed = (authorName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Someone" : trimmed
    }

    var displayBody: String { body ?? "" }

    /// The server decides who may remove a comment — anyone who can edit the
    /// element, or whoever wrote it — and says so by offering the link.
    var canDelete: Bool { hasLink(.delete) }

    static func == (lhs: BlockComment, rhs: BlockComment) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AddCommentCommand: Encodable {
    var body: String
}
