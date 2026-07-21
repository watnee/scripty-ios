//
//  InvitationsModel.swift
//  scripty
//
//  Who can see a screenplay: the people who already can, and the people who
//  have been invited to.
//
//  The invitation surface is gated on a link the project advertises, which the
//  server only offers when its `api-invitations` flag is on. So a deployment
//  that has not enabled invitations over the API shows nothing of it at all,
//  rather than a button that fails.
//
//  The access list is not behind that flag, and is deliberately loaded even
//  when invitations are off — a role or a team grants access with no invitation
//  involved, so "nobody has been invited" was never the same answer as "nobody
//  else can see this".
//

import Foundation
import Observation

@Observable
@MainActor
final class InvitationsModel {
    private let app: AppModel
    /// The project's `invitations` link. Nil where the deployment has not
    /// turned the API's invitation surface on — the access list still loads.
    private let source: HALLink?
    /// The project's `contact-suggestions` link, when it advertised one. Nil
    /// simply means no autofill — the invite field still works by hand.
    private let contactsSource: HALLink?
    /// The project's `access` link.
    private let accessSource: HALLink?

    private(set) var invitations: [Invitation] = []
    private(set) var people: [ProjectAccessUser] = []
    private(set) var links = HALLinks()
    private(set) var isLoading = false
    private(set) var isWorking = false
    var errorMessage: String?

    private(set) var suggestions: [ContactSuggestion] = []
    private var suggestTask: Task<Void, Never>?

    var canInvite: Bool { links.contains(.sendInvitation) }
    var canSuggest: Bool { contactsSource != nil }
    var knowsWhoHasAccess: Bool { accessSource != nil }

    var collaborators: [Invitation] { invitations.filter { !$0.isViewOnly } }
    var readers: [Invitation] { invitations.filter(\.isViewOnly) }

    init(app: AppModel,
         source: HALLink?,
         contactsSource: HALLink? = nil,
         accessSource: HALLink? = nil) {
        self.app = app
        self.source = source
        self.contactsSource = contactsSource
        self.accessSource = accessSource
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let source {
            do {
                let collection: HALCollection<Invitation> = try await app.client.fetch(from: source)
                adopt(collection)
                errorMessage = nil
            } catch {
                report(error)
            }
        }
        await loadAccess()
    }

    /// Quiet on failure. This list is context beside the invitations, and an
    /// alert about it would sit on top of the thing the writer came here to do.
    private func loadAccess() async {
        guard let accessSource else { return }
        if let collection: HALCollection<ProjectAccessUser> =
            try? await app.client.fetch(from: accessSource) {
            people = collection.items
        }
    }

    /// Invites an address. Answers the same whether or not that address already
    /// has an account — the server will not say, so the client cannot either.
    @discardableResult
    func invite(_ email: String, viewOnly: Bool) async -> Bool {
        guard let link = links[.sendInvitation] else { return false }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await act(link, method: "POST",
                         body: SendInvitationCommand(email: trimmed, teamId: nil, viewOnly: viewOnly))
    }

    /// Looks up contacts matching what has been typed so far, debounced so a
    /// fast typist does not fire a request per keystroke. An empty query clears
    /// the list rather than asking the server for everyone.
    func suggestContacts(matching query: String) {
        suggestTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let contactsSource, trimmed.count >= 2 else {
            suggestions = []
            return
        }
        suggestTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let link = contactsSource.addingQuery(["q": trimmed])
            do {
                let collection: HALCollection<ContactSuggestion> = try await app.client.fetch(from: link)
                guard !Task.isCancelled else { return }
                suggestions = collection.items
            } catch {
                // Autofill is a convenience; a failed lookup just offers nothing
                // rather than interrupting the writer with an error.
                suggestions = []
            }
        }
    }

    func clearSuggestions() {
        suggestTask?.cancel()
        suggestions = []
    }

    @discardableResult
    func revoke(_ invitation: Invitation) async -> Bool {
        guard let link = invitation.link(.revoke) else { return false }
        return await act(link, method: "DELETE")
    }

    private func act(_ link: HALLink, method: String, body: (any Encodable)? = nil) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let collection: HALCollection<Invitation> = try await app.client.fetch(
                from: link, method: method, body: body)
            adopt(collection)
            errorMessage = nil
            return true
        } catch APIError.server(let status) where status == 429 {
            // Sending is rate limited per user; say so plainly rather than
            // reporting it as a failure the writer can retry immediately.
            errorMessage = "Too many invitations sent recently. Try again later."
            return false
        } catch {
            report(error)
            return false
        }
    }

    private func adopt(_ collection: HALCollection<Invitation>) {
        invitations = collection.items
        links = collection.links
    }

    private func report(_ error: Error) {
        app.handle(error)
        errorMessage = error.localizedDescription
    }
}
