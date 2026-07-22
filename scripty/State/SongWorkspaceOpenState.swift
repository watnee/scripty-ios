//
//  SongWorkspaceOpenState.swift
//  scripty
//
//  Which songs are expanded in the all-songs workspace, remembered per project.
//
//  The workspace stacks every song as its own collapsible section, and which
//  ones a writer left open is part of where they were working — reopening to a
//  wall of collapsed songs loses that. The web remembers the same thing under
//  the same key, so the two clients open to the same set.
//
//  Nothing here reaches the server. This is a choice about looking, scoped to
//  the one project the workspace belongs to.
//

import Foundation

struct SongWorkspaceOpenState {
    let projectId: Int
    private let defaults: UserDefaults

    init(projectId: Int, defaults: UserDefaults = .standard) {
        self.projectId = projectId
        self.defaults = defaults
    }

    /// The web writes a JSON array of the open song ids; the dot-spelled prefix
    /// is its own, kept so both clients read one store.
    private var key: String { "scripty.songWorkspace.open.\(projectId)" }

    /// The songs left open, or an empty set the first time — a fresh workspace
    /// opens collapsed, as the web does.
    func load() -> Set<Int> {
        guard let raw = defaults.string(forKey: key),
              let data = raw.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    /// Stored sorted so the value is stable to eyeball and does not churn in
    /// storage as songs are toggled in a different order.
    func save(_ ids: Set<Int>) {
        guard let data = try? JSONEncoder().encode(ids.sorted()),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        defaults.set(raw, forKey: key)
    }
}
