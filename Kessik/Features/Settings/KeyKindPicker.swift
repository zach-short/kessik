import SwiftUI

/// Picks the login key: the ed25519 key, or the Secure Enclave key that needs Face ID.
/// Without a Secure Enclave, as in the simulator, the picker is off and says why.
struct KeyKindPicker: View {
    @Binding var kind: LoginKeyKind

    var body: some View {
        Picker("Key type", selection: Binding(get: { kind }, set: pick)) {
            ForEach(LoginKeyKind.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .disabled(!EnclaveKey.isAvailable)
        if !EnclaveKey.isAvailable {
            Text("This device has no Secure Enclave, so the app uses the ed25519 key.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func pick(_ new: LoginKeyKind) {
        UserDefaults.standard.set(new.rawValue, forKey: SettingsKey.loginKeyKind)
        kind = new
    }
}
