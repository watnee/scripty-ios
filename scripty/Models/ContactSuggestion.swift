//
//  ContactSuggestion.swift
//  scripty
//
//  A name-and-address the server offers while an invite is being typed.
//
//  Scoped to one project and to people the sender can already see, so filling
//  in an address is a convenience, not a way to discover who else uses Scripty.
//

import Foundation

struct ContactSuggestion: Decodable, Identifiable, Hashable {
    var name: String?
    var email: String
    /// Where the server knew this person from — "Collaborator", "Cast", and so
    /// on. Shown beside the name so an ambiguous match can be told apart.
    var sourceLabel: String?

    var id: String { email }

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? email : trimmed
    }
}
