//
//  Team.swift
//  scripty
//
//  A production's people. Managed by an admin, which is why the API root only
//  advertises the `teams` rel to someone allowed to see them.
//
//  The resource carries just an id and a name; which productions a team covers
//  is not on the team itself but on each project (its `teams` badge), so the
//  assignment screen reads the current state from the project list.
//

import Foundation

struct Team: Decodable, Identifiable, Hashable, HALResource {
    let id: Int
    var name: String?
    let links: HALLinks?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case links = "_links"
    }

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Team" : trimmed
    }

    var canRename: Bool { hasLink(.update) }
    var canDelete: Bool { hasLink(.delete) }
    var canAssign: Bool { hasLink(.assignProductions) }
}

struct TeamCommand: Encodable {
    var name: String
}

/// The productions a team covers, replaced wholesale. An empty list clears
/// them — the server reads a missing list and an empty one differently, so
/// this always sends one.
struct AssignProductionsCommand: Encodable {
    var projectIds: [Int]
}
