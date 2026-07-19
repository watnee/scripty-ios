//
//  ActorEditorSheet.swift
//  scripty
//
//  Create or edit one actor in the project's cast. Mirrors the character
//  editor: a short form, a save spinner, and the server's message inline
//  when the write is refused.
//

import SwiftUI

struct ActorEditorSheet: View {
    let casting: CastingModel
    let actor: ScriptyActor?   // nil = create

    @Environment(\.dismiss) private var dismiss
    @State private var first: String
    @State private var last: String
    @State private var phone: String
    @State private var email: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(casting: CastingModel, actor: ScriptyActor?) {
        self.casting = casting
        self.actor = actor
        _first = State(initialValue: actor?.first ?? "")
        _last = State(initialValue: actor?.last ?? "")
        _phone = State(initialValue: actor?.phone ?? "")
        _email = State(initialValue: actor?.email ?? "")
    }

    /// A name is the only thing the cast list can't do without; contact
    /// details are optional, but a typed email has to look like one.
    private var canSave: Bool {
        !first.trimmingCharacters(in: .whitespaces).isEmpty
            && !last.trimmingCharacters(in: .whitespaces).isEmpty
            && emailIsPlausible
            && !isSaving
    }

    private var emailIsPlausible: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $first)
                        .textContentType(.givenName)
                    TextField("Last name", text: $last)
                        .textContentType(.familyName)
                }
                Section("Contact") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(actor == nil ? "New Actor" : "Edit Actor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(!canSave)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        let trimmedFirst = first.trimmingCharacters(in: .whitespaces)
        let trimmedLast = last.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        Task {
            let succeeded: Bool
            if let actor {
                succeeded = await casting.updateActor(
                    actor, first: trimmedFirst, last: trimmedLast,
                    phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                    email: trimmedEmail.isEmpty ? nil : trimmedEmail)
            } else {
                succeeded = await casting.createActor(
                    first: trimmedFirst, last: trimmedLast,
                    phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                    email: trimmedEmail.isEmpty ? nil : trimmedEmail)
            }
            isSaving = false
            if succeeded {
                dismiss()
            } else {
                errorMessage = casting.errorMessage
                casting.errorMessage = nil   // shown inline; don't also alert the list
            }
        }
    }
}
