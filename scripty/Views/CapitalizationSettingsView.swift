//
//  CapitalizationSettingsView.swift
//  scripty
//
//  Editor preferences: which elements are typed in ALL CAPS. The web app puts
//  these on a menu; on iOS they read better as a settings sheet of toggles.
//
//  Each toggle persists on the spot through the shared settings, which posts
//  only the field that changed. The screen is presented only when the root
//  advertised the preference, so the toggles always have somewhere to save to.
//

import SwiftUI

struct CapitalizationSettingsView: View {
    let app: AppModel

    @Environment(\.dismiss) private var dismiss

    private var settings: CapitalizationSettings { CapitalizationSettings.shared }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(CapitalizedElement.allCases, id: \.self) { element in
                        Toggle(element.label, isOn: binding(for: element))
                    }
                } header: {
                    Text("Automatic Capitalization")
                } footer: {
                    Text("Type these elements in capitals. Exports carry the same case, so a change here also changes the PDF, Word and Final Draft files you export.")
                }
            }
            .navigationTitle("Editor Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func binding(for element: CapitalizedElement) -> Binding<Bool> {
        Binding(
            get: { settings.isOn(element) },
            set: { newValue in
                Task { await settings.set(element, on: newValue, using: app.client) }
            })
    }
}
