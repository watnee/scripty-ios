//
//  TeamsView.swift
//  scripty
//
//  Managing production teams: the set of them, and which productions each one
//  covers.
//
//  Reached from the projects sidebar only when the API root advertised the
//  `teams` rel — i.e. for someone allowed to manage them. Which productions a
//  team currently covers is not carried on the team resource, so the assignment
//  sheet reads it from the projects that already show the team's badge.
//

import SwiftUI

struct TeamsView: View {
    @State private var model: TeamsModel
    /// The projects to choose from, and the source of truth for what a team
    /// currently covers — a project shows a team's badge exactly when it is
    /// assigned to it.
    let projects: [Project]

    @Environment(\.dismiss) private var dismiss
    @State private var isCreating = false
    @State private var renamingTeam: Team?
    @State private var assigningTeam: Team?
    @State private var pendingDelete: Team?

    init(app: AppModel, source: HALLink, projects: [Project]) {
        _model = State(initialValue: TeamsModel(app: app, source: source))
        self.projects = projects
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.teams) { team in
                    row(team)
                }
            }
            .overlay { emptyState }
            .navigationTitle("Teams")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New Team", systemImage: "plus")
                    }
                    .disabled(model.isWorking)
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .sheet(isPresented: $isCreating) {
                TeamNameSheet(name: "", heading: "New Team") { name in
                    await model.create(name: name)
                }
            }
            .sheet(item: $renamingTeam) { team in
                TeamNameSheet(name: team.displayName, heading: "Rename Team") { name in
                    await model.rename(team, to: name)
                }
            }
            .sheet(item: $assigningTeam) { team in
                AssignProductionsSheet(
                    team: team,
                    projects: projects,
                    initiallyAssigned: assignedProjectIds(for: team)) { ids in
                        await model.assignProductions(team, projectIds: ids)
                    }
            }
            .alert("Delete Team", isPresented: deleteBinding) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    let team = pendingDelete
                    pendingDelete = nil
                    Task {
                        guard let team else { return }
                        await model.delete(team)
                    }
                }
            } message: {
                Text("Remove “\(pendingDelete?.displayName ?? "")”? The productions it "
                     + "covers are not deleted.")
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private func row(_ team: Team) -> some View {
        let assigned = assignedProjectIds(for: team).count
        return VStack(alignment: .leading, spacing: 2) {
            Text(team.displayName)
            Text(assigned == 0
                 ? "No productions"
                 : "\(assigned) " + (assigned == 1 ? "production" : "productions"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if team.canAssign { assigningTeam = team }
        }
        .swipeActions(edge: .trailing) {
            if team.canDelete {
                Button(role: .destructive) {
                    pendingDelete = team
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            if team.canRename {
                Button {
                    renamingTeam = team
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if team.canAssign {
                Button {
                    assigningTeam = team
                } label: {
                    Label("Assign Productions", systemImage: "film.stack")
                }
            }
            if team.canRename {
                Button {
                    renamingTeam = team
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }
            if team.canDelete {
                Button(role: .destructive) {
                    pendingDelete = team
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    /// The productions a team covers now, read off the projects that show its
    /// badge. Matching is by name because that badge is the only assignment the
    /// project resource exposes.
    private func assignedProjectIds(for team: Team) -> [Int] {
        let name = team.displayName
        return projects
            .filter { ($0.teams ?? []).contains(name) }
            .map(\.id)
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.teams.isEmpty {
            if model.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView {
                    Label("No Teams Yet", systemImage: "person.3")
                } description: {
                    Text("Create a team to group the productions a set of people works on.")
                } actions: {
                    Button("New Team") { isCreating = true }
                }
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}

/// Name entry for creating or renaming a team.
private struct TeamNameSheet: View {
    @State var name: String
    let heading: String
    let action: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Team name", text: $name)
                    .focused($focused)
                    .onSubmit { save() }
            }
            .navigationTitle(heading)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        Task {
            let ok = await action(name)
            isSaving = false
            if ok { dismiss() }
        }
    }
}

/// Picks which productions a team covers. Starts from what the team covers now,
/// and sends the whole set back — the server replaces the assignment wholesale.
private struct AssignProductionsSheet: View {
    let team: Team
    let projects: [Project]
    let initiallyAssigned: [Int]
    let action: ([Int]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int> = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                if projects.isEmpty {
                    Text("There are no productions to assign yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(projects) { project in
                    Button {
                        toggle(project.id)
                    } label: {
                        HStack {
                            Text(project.displayTitle)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selected.contains(project.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle(team.displayName)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                    }
                }
            }
            .onAppear { selected = Set(initiallyAssigned) }
        }
    }

    private func toggle(_ id: Int) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func save() {
        isSaving = true
        Task {
            let ok = await action(Array(selected))
            isSaving = false
            if ok { dismiss() }
        }
    }
}
