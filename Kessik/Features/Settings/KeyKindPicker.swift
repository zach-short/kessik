import SwiftUI

/// Picks the login key: the key in the Keychain, or the Secure Enclave key that needs Face ID.
/// Without a Secure Enclave, as in the simulator, the picker is off and says why.
struct KeyKindPicker: View {
    @Binding var kind: LoginKeyKind
    /// The type of the key in the Keychain, such as "Ed25519" or "ECDSA P-384". It names the `.ed25519` option.
    var keychainLabel: String

    var body: some View {
        Picker("Key type", selection: Binding(get: { kind }, set: pick)) {
            ForEach(LoginKeyKind.allCases) { option in
                Text(option == .ed25519 ? keychainLabel : option.label).tag(option)
            }
        }
        .disabled(!EnclaveKey.isAvailable)
        if !EnclaveKey.isAvailable {
            Text("This device has no Secure Enclave, so the app uses the key in the Keychain.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func pick(_ new: LoginKeyKind) {
        UserDefaults.standard.set(new.rawValue, forKey: SettingsKey.loginKeyKind)
        kind = new
    }
}
