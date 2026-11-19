import EVCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Car") {
                    LabeledContent("Model", value: model.identity.name)
                    LabeledContent("Usable battery", value: String(format: "%.1f kWh", model.profile.usableCapacityKwh))
                    if model.identity.model.reportsPackEnergy {
                        Text("Learned from your car's own readings after a few charges.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Control PIN") {
                    LabeledContent("Saved", value: model.hasPin ? "Yes" : "No")
                    if model.hasPin {
                        Button("Forget control PIN", role: .destructive) { model.forgetPin() }
                    }
                }

                Section {
                    Button("Sign out of MG", role: .destructive) { confirmSignOut = true }
                } footer: {
                    Text("Signing out removes your MG login, control PIN and saved car data from this iPhone.")
                }

                Section("About") {
                    Text("An independent app. Not made by, endorsed by or affiliated with MG Motor India or SAIC. Built on the open-source Volta app and mg-ismart-india-client.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign out of MG?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            }
        }
    }
}
