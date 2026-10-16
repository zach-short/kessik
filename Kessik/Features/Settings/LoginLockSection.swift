import SwiftUI

/// The Face ID toggle. Turning it on or off asks for Face ID first, so the check works before
/// a login depends on it, and so someone else holding the phone cannot turn it off.
struct LoginLockSection: View {
    @AppStorage(SettingsKey.requireFaceID) private var required = false
    @State private var checking = false
    @State private var status: String?

    var authenticator: Authenticator = DeviceOwnerAuthenticator()

    var body: some View {
        Section {
            Toggle("Require Face ID to log in", isOn: Binding(get: { required }, set: change))
                .disabled(checking)
        } header: {
            Text("Face ID")
        } footer: {
            Text(status ?? "Each login asks for Face ID, or the passcode, before the app uses the key or a saved password.")
        }
    }

    private func change(_ on: Bool) {
        checking = true
        status = nil
        Task {
            defer { checking = false }
            do {
                try await authenticator.authenticate(reason: on ? "Require Face ID to log in" : "Stop requiring Face ID to log in")
                required = on
            } catch LoginGate.Failure.canceled {
                // The toggle stays as it was.
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
