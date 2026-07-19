//
//  ShareView.swift
//  scripty
//
//  Who has access to a screenplay, and inviting more.
//
//  Collaborators and readers are listed apart because they are different
//  grants: a collaborator gets an account and can write, a reader gets a link
//  and can only read. Conflating them would make it easy to hand out the wrong
//  one.
//
//  There is no link to copy here. The server never returns an invite token or
//  URL, and the invitee's journey — accepting, or opening a view-only link —
//  happens in email and a browser, where it already works and where no account
//  is needed.
//

import SwiftUI

struct ShareView: View {
    @State private var model: InvitationsModel
    let projectTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var draftEmail = ""
    @State private var inviteAsReader = false
    @State private var pendingRevoke: Invitation?
    @State private var sentNotice: String?
    @FocusState private var emailFocused: Bool

    init(app: AppModel, source: HALLink, projectTitle: String) {
        _model = State(initialValue: InvitationsModel(app: app, source: source))
        self.projectTitle = projectTitle
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.canInvite {
                    inviteSection
                }

                if !model.collaborators.isEmpty {
                    Section("Collaborators") {
                        ForEach(model.collaborators) { row($0) }
                    }
                }

                if !model.readers.isEmpty {
                    Section {
                        ForEach(model.readers) { row($0) }
                    } header: {
                        Text("View-Only Readers")
                    } footer: {
                        Text("Readers open the screenplay from a link in their email. "
                             + "They cannot edit it.")
                    }
                }

                if model.collaborators.isEmpty && model.readers.isEmpty && !model.isLoading {
                    Section {
                        Text("Nobody else has been invited to “\(projectTitle)”.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Share")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .alert("Remove Access", isPresented: revokeBinding) {
                Button("Cancel", role: .cancel) { pendingRevoke = nil }
                Button("Remove", role: .destructive) {
                    let invitation = pendingRevoke
                    pendingRevoke = nil
                    Task {
                        guard let invitation else { return }
                        await model.revoke(invitation)
                    }
                }
            } message: {
                Text("Revoke the invitation for \(pendingRevoke?.displayEmail ?? "")?")
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var inviteSection: some View {
        Section {
            TextField("Email address", text: $draftEmail)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #if !os(macOS)
                .keyboardType(.emailAddress)
                #endif
                .focused($emailFocused)

            Picker("Access", selection: $inviteAsReader) {
                Text("Can edit").tag(false)
                Text("Can read").tag(true)
            }
            .pickerStyle(.segmented)

            Button {
                send()
            } label: {
                if model.isWorking {
                    ProgressView()
                } else {
                    Text("Send Invitation")
                }
            }
            .disabled(draftEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || model.isWorking)
        } header: {
            Text("Invite")
        } footer: {
            // The server will not say whether an address is already registered,
            // so neither does this — the confirmation is deliberately the same
            // either way.
            Text(sentNotice
                 ?? "They will get an email. Scripty does not say whether an address "
                 + "already has an account.")
        }
    }

    private func row(_ invitation: Invitation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(invitation.displayEmail)
            HStack(spacing: 6) {
                if let status = invitation.statusLabel, !status.isEmpty {
                    Text(status)
                }
                if let team = invitation.teamName, !team.isEmpty {
                    Text("· \(team)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing) {
            if invitation.canRevoke {
                Button(role: .destructive) {
                    pendingRevoke = invitation
                } label: {
                    Label("Remove", systemImage: "person.badge.minus")
                }
            }
        }
    }

    private func send() {
        let email = draftEmail
        let asReader = inviteAsReader
        draftEmail = ""
        emailFocused = false
        Task {
            if await model.invite(email, viewOnly: asReader) {
                sentNotice = "Invitation sent to \(email)."
            }
        }
    }

    private var revokeBinding: Binding<Bool> {
        Binding(get: { pendingRevoke != nil },
                set: { if !$0 { pendingRevoke = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}
