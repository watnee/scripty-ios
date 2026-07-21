//
//  ProjectAccess.swift
//  scripty
//
//  Who can already see a screenplay.
//
//  Not the same list as the invitations. A role or a team carries access with
//  no invitation involved, so a project can be readable by people no invitation
//  names — and "nobody else has been invited" was quietly answering a question
//  the writer had not asked.
//
//  The labels arrive rendered. The reasons someone is here come from the
//  server's own access rules, and restating them in Swift would let the two
//  drift apart without anything failing.
//

import Foundation

struct ProjectAccessUser: Decodable, Identifiable, Hashable, HALResource {
    var displayName: String?
    var accessLabel: String?
    var canEdit: Bool?
    var permissionLabel: String?
    let links: HALLinks?

    private enum CodingKeys: String, CodingKey {
        case displayName, accessLabel, canEdit, permissionLabel
        case links = "_links"
    }

    /// There is no id on the wire — the server sends people, not records — so
    /// the name identifies the row. Two people with the same display name would
    /// collide in the list; the server sorts by it and includes the email where
    /// names repeat, so the collision is the server's to avoid.
    var id: String { displayName ?? "" }

    var name: String {
        let trimmed = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Someone" : trimmed
    }

    var writes: Bool { canEdit ?? false }

    var permission: String { permissionLabel ?? (writes ? "Can edit" : "View only") }
}
