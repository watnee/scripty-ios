//
//  CapitalizationPreferences.swift
//  scripty
//
//  The `/api/preferences/capitalization` resource: four booleans and the links
//  to read and update them. The server omits nothing, but an absent field is
//  read as on so an older or partial response still lands on the historic
//  all-caps default rather than a spurious all-off.
//

import Foundation

/// The four screenplay elements the server capitalizes. Their raw values are
/// the field names the `/api/preferences/capitalization` payload uses.
enum CapitalizedElement: String, CaseIterable, Sendable {
    case scene, character, transition, shot

    var label: String {
        switch self {
        case .scene: return "Scene Headings"
        case .character: return "Character Cues"
        case .transition: return "Transitions"
        case .shot: return "Shots"
        }
    }
}

struct CapitalizationPreferences: Decodable, HALResource {
    let values: [CapitalizedElement: Bool]
    let links: HALLinks?

    private enum CodingKeys: String, CodingKey {
        case scene, character, transition, shot
        case links = "_links"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var values: [CapitalizedElement: Bool] = [:]
        values[.scene] = try container.decodeIfPresent(Bool.self, forKey: .scene) ?? true
        values[.character] = try container.decodeIfPresent(Bool.self, forKey: .character) ?? true
        values[.transition] = try container.decodeIfPresent(Bool.self, forKey: .transition) ?? true
        values[.shot] = try container.decodeIfPresent(Bool.self, forKey: .shot) ?? true
        self.values = values
        self.links = try container.decodeIfPresent(HALLinks.self, forKey: .links)
    }

    /// A partial update: only the element that changed is sent, so the server's
    /// "absent field keeps its stored value" rule leaves the others alone.
    struct Update: Encodable {
        let element: CapitalizedElement
        let on: Bool

        private enum DynamicKey: String, CodingKey {
            case scene, character, transition, shot
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicKey.self)
            try container.encode(on, forKey: DynamicKey(rawValue: element.rawValue)!)
        }
    }
}
