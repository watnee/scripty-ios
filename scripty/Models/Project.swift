//
//  Project.swift
//  scripty
//

import Foundation

/// A screenplay project. The server omits null fields, so everything but
/// `id` is optional.
struct Project: Decodable, Identifiable, Hashable, HALResource {
    let id: Int
    var title: String?
    var screenplayTitle: String?
    var writers: String?
    var contactInfo: String?
    var screenplayVersion: String?
    var lastEdited: Date?
    var teams: [String]?
    /// Whether this is the current user's default project (server key `default`).
    var isDefault: Bool?
    let links: HALLinks?

    private enum CodingKeys: String, CodingKey {
        case id, title, screenplayTitle, writers, contactInfo, screenplayVersion, lastEdited, teams
        case isDefault = "default"
        case links = "_links"
    }

    var displayTitle: String {
        let name = screenplayTitle ?? title ?? ""
        return name.isEmpty ? "Untitled Project" : name
    }
}

struct CreateProjectCommand: Encodable {
    var title: String
    var teamIds: [Int] = []
}

/// Omitting `teamIds` leaves team assignments untouched on the server, so a
/// plain rename never disturbs them and reassigning teams never touches the
/// title. The title-page fields are likewise left alone when nil, so a rename
/// does not wipe the front matter and vice versa.
struct EditProjectCommand: Encodable {
    var title: String
    var screenplayTitle: String?
    var writers: String?
    var contactInfo: String?
    var screenplayVersion: String?
    var teamIds: [Int]?
}

/// One team the project could belong to, and whether it does now — a row in the
/// `projectTeams` collection. The picker ticks the assigned ones and sends the
/// ticked ids back through the project's `update` affordance (`teamIds`).
struct ProjectTeamOption: Decodable, Identifiable, Hashable {
    let id: Int
    var name: String
    var assigned: Bool
}
