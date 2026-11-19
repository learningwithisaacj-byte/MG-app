import EVCore
import OpenMeteo
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false
    @State private var precoolOn = true
    @State private var thresholdC = PrecoolAdvisor.defaultThresholdC
    @State private var parksInShade = false

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

                Section {
                    Toggle("Suggest AC on hot days", isOn: $precoolOn)
                    if precoolOn {
                        Stepper("Above \(thresholdC) °C", value: $thresholdC, in: 24...40)
                        Toggle("I usually park in shade", isOn: $parksInShade)
                    }
                } header: {
                    Text("Hot-day AC")
                } footer: {
                    Text("Between 7 am and 7 pm, when your car is parked with the AC off and both the air and the cabin are above this, the app offers to cool it. At most once every two hours, and the AC only goes on after Face ID. \(OpenMeteoClient.attribution).")
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
            .onAppear {
                precoolOn = model.car.precoolEnabled
                thresholdC = model.car.precoolThresholdC
                parksInShade = model.car.parksInShade
            }
            .onChange(of: precoolOn) { _, v in model.car.precoolEnabled = v; model.precoolSettingsChanged() }
            .onChange(of: thresholdC) { _, v in model.car.precoolThresholdC = v; model.precoolSettingsChanged() }
            .onChange(of: parksInShade) { _, v in model.car.parksInShade = v; model.precoolSettingsChanged() }
            .confirmationDialog("Sign out of MG?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            }
        }
    }
}
