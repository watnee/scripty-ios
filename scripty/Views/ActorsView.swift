//
//  ActorsView.swift
//  scripty
//
//  The cast list for a project — the iPad counterpart of the web app's
//  Casting screen. Add, edit and remove actors, each row showing the
//  headshot the server holds. Every affordance is gated on the links the
//  server advertised.
//

import SwiftUI

struct ActorsView: View {
    let casting: CastingModel

    @Environment(\.dismiss) private var dismiss
    @State private var editingActor: ScriptyActor?
    @State private var showingCreate = false
    @State private var searchText = ""

    private var shown: [ScriptyActor] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return casting.actors }
        return casting.actors.filter { actor in
            [actor.displayName, actor.email ?? "", actor.phone ?? ""]
                .contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(shown) { actor in
                    row(for: actor)
                }
            }
            .overlay { emptyState }
            .searchable(text: $searchText, prompt: "Search cast")
            .navigationTitle("Casting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await casting.load() }
            .refreshable { await casting.load() }
            .sheet(isPresented: $showingCreate) {
                ActorEditorSheet(casting: casting, actor: nil)
            }
            .sheet(item: $editingActor) { actor in
                ActorEditorSheet(casting: casting, actor: actor)
            }
            .alert("Casting", isPresented: errorBinding) {
                Button("OK", role: .cancel) { casting.errorMessage = nil }
            } message: {
                Text(casting.errorMessage ?? "")
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for actor: ScriptyActor) -> some View {
        Button {
            if actor.hasLink(.update) {
                editingActor = actor
            }
        } label: {
            HStack(spacing: 12) {
                HeadshotThumbnail(casting: casting, actor: actor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(actor.displayName)
                        .font(.headline)
                    if let contact = actor.contactLine {
                        Text(contact)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .trailing) {
            if actor.hasLink(.delete) {
                Button(role: .destructive) {
                    Task { await casting.deleteActor(actor) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if shown.isEmpty {
            if casting.isLoading {
                ProgressView()
            } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ContentUnavailableView(
                    "No Actors",
                    systemImage: "person.crop.rectangle.stack",
                    description: Text(casting.canCreate
                        ? "Add an actor to start casting your characters."
                        : "Nobody has been added to this project's cast."))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        if casting.canCreate {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreate = true
                } label: {
                    Label("New Actor", systemImage: "plus")
                }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { casting.errorMessage != nil },
                set: { if !$0 { casting.errorMessage = nil } })
    }
}

/// A small round headshot, or the silhouette placeholder while it loads or
/// when the actor has no image on file.
struct HeadshotThumbnail: View {
    let casting: CastingModel
    let actor: ScriptyActor
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let data = casting.headshotData(for: actor),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .task(id: actor.id) { await casting.loadHeadshot(for: actor) }
    }
}
