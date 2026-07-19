//
//  InvitationsModel.swift
//  scripty
//
//  Who has been invited to a screenplay, and inviting more.
//
//  The whole surface is gated on a link the project advertises, which the
//  server only offers when its `api-invitations` flag is on. So a deployment
//  that has not enabled invitations over the API shows nothing at all here,
//  rather than a button that fails.
//

import Foundation
import Observation

@Observable
@MainActor
final class InvitationsModel {
    private let app: AppModel
    private let source: HALLink

    private(set) var invitations: [Invitation] = []
    private(set) var links = HALLinks()
    private(set) var isLoading = false
    private(set) var isWorking = false
    var errorMessage: String?

    var canInvite: Bool { links.contains(.sendInvitation) }

    var collaborators: [Invitation] { invitations.filter { !$0.isViewOnly } }
    var readers: [Invitation] { invitations.filter(\.isViewOnly) }

    init(app: AppModel, source: HALLink) {
        self.app = app
        self.source = source
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let collection: HALCollection<Invitation> = try await app.client.fetch(from: source)
            adopt(collection)
            errorMessage = nil
        } catch {
            report(error)
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
