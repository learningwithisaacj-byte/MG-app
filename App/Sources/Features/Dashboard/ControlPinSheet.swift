import MGKit
import SwiftUI

/// Asks for the 4-digit MG control PIN the first time a command is sent. Only its hash is kept.
struct ControlPinSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let command: RemoteCommand
    @State private var pin = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("4-digit control PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                        .onChange(of: pin) { _, new in pin = String(new.filter(\.isNumber).prefix(4)) }
                } footer: {
                    Text("The PIN you set in the MG app for remote commands. MG checks it before \(command.label.lowercased()) is sent. Only a hash of it is kept on this iPhone, and wrong tries count against MG's limit.")
                }
            }
            .navigationTitle("Control PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(command.label) {
                        let entered = pin
                        dismiss()
                        Task { await model.enterPin(entered) }
                    }
                    .disabled(pin.count != 4)
                }
            }
            .onAppear { focused = true }
        }
    }
}
