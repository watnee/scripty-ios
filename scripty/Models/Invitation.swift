//
//  Invitation.swift
//  scripty
//
//  Someone invited to a screenplay: a collaborator who will get an account, or
//  a view-only reader who will not.
//
//  Carries no token and no invite link. The server does not send one, and the
//  client should not want one — the invitee's journey happens in email and a
//  browser, which is where it already works.
//

import Foundation

struct Invitation: Decodable, Identifiable, Hashable, HALResource {
    let id: Int
    var email: String?
    var teamName: String?
    var statusLabel: String?
    var viewOnly: Bool?
    let links: HALLinks?

    private enum CodingKeys: String, CodingKey {
        case id, email, teamName, statusLabel, viewOnly
        case links = "_links"
    }

    var displayEmail: String {
        let trimmed = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown address" : trimmed
    }

    var isViewOnly: Bool { viewOnly ?? false }

    var canRevoke: Bool { hasLink(.revoke) }

    static func == (lhs: Invitation, rhs: Invitation) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct SendInvitationCommand: Encodable {
    var email: String
    var teamId: Int?
    /// A reader rather than a collaborator.
    var viewOnly: Bool
}

/// One team a collaborator can be invited into.
///
/// Inviting an editor requires a team, and the only valid choices are the ones
/// the project is already assigned to. The server sends this short list — an id
/// and a name — because `/api/team` is admin-only, so an ordinary editor has no
/// other way to learn a team's id.
struct InviteTeam: Decodable, Identifiable, Hashable, HALResource {
    let id: Int
    var name: String?
    let links: HALLinks?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case links = "_links"
    }

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled team" : trimmed
    }

    static func == (lhs: InviteTeam, rhs: InviteTeam) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
