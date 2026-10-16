import SwiftUI

/// The Mac form's jump host fields, folded away until opened. Empty fields mean no jump host.
struct JumpHostFields: View {
    @Binding var draft: JumpHostDraft
    /// True when the Keychain already holds a password for the jump host as typed.
    var hasSavedPassword: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            field("Hostname", prompt: "jump.example.com", text: $draft.hostname, keyboard: .URL)
            field("Port", prompt: "22", text: $draft.port, keyboard: .numberPad)
            field("Username", prompt: "user on the jump host", text: $draft.username)
            LabeledContent("Password") {
                SecureField("Password", text: $draft.password,
                            prompt: Text(hasSavedPassword ? "Saved" : "Optional"))
                    .multilineTextAlignment(.trailing)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } label: {
            LabeledContent("Jump host") {
                Text(draft.jump?.address ?? "None")
                    .font(Theme.mono)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func field(_ label: String, prompt: String, text: Binding<String>,
                       keyboard: UIKeyboardType = .default) -> some View {
        LabeledContent(label) {
            TextField(label, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .font(Theme.mono)
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
        }
    }
}
