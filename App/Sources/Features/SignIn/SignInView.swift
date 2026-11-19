import MGKit
import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var phone = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    private var canSubmit: Bool {
        phone.filter(\.isNumber).count >= 10 && !password.isEmpty && !busy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mobile number", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    SecureField("i-SMART password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Your MG i-SMART owner account")
                } footer: {
                    Text("""
                    Signing in here signs the official MG app out, because MG allows one session at a time. \
                    Your login stays in this iPhone's Keychain and is only sent to MG.
                    """)
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Text(busy ? "Signing in…" : "Sign in")
                            Spacer()
                            if busy { ProgressView() }
                        }
                    }
                    .disabled(!canSubmit)
                } footer: {
                    Text("If multi-factor login is on for your MG account, turn it off in the MG app's security settings first. Each wrong password counts against MG's daily limit, so a rejected password is never retried.")
                }
            }
            .navigationTitle("MG EV")
        }
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.signIn(phone: phone, password: password)
        } catch let e as IsmartError {
            error = e.userMessage
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    SignInView().environment(AppModel())
}
