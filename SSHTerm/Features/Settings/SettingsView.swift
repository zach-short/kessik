import SwiftUI

enum SettingsKey {
    static let terminalFontSize = "terminalFontSize"
    static let hapticsEnabled = "hapticsEnabled"
    static let sessionsAddress = "sessionsAddress"
    static let rememberPasswords = "rememberPasswords"
}

struct SettingsView: View {
    @AppStorage(SettingsKey.terminalFontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Terminal") {
                    Stepper(value: $fontSize, in: 9...24, step: 1) {
                        HStack {
                            Text("Text size")
                            Spacer()
                            Text("\(Int(fontSize)) pt")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Text("claude --continue")
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                }

                Section("Feedback") {
                    Toggle("Haptics on key taps", isOn: $hapticsEnabled)
                }

                KeySection()
                PasswordsSection()

                Section {
                    LabeledContent("Version", value: Bundle.main.shortVersion)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
        }
    }
}

/// The phone's ed25519 key: make one, copy or install the public half, replace or delete it.
private struct KeySection: View {
    @Environment(MacLink.self) private var link
    @State private var publicLine = DeviceKey.load().map(DeviceKey.publicLine(for:))
    @State private var status: String?
    @State private var installing = false
    @State private var confirmReplace = false
    @State private var confirmDelete = false

    var body: some View {
        Section {
            if let publicLine {
                Text(publicLine)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
                Button("Copy public key", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = publicLine
                    status = "Copied. Add it to ~/.ssh/authorized_keys on the Mac."
                }
                ShareLink(item: publicLine) { Label("Share public key", systemImage: "square.and.arrow.up") }
                Button {
                    Task { await install(publicLine) }
                } label: {
                    HStack {
                        Label("Add to \(link.host.hostname)", systemImage: "laptopcomputer.and.arrow.down")
                        if installing { Spacer(); ProgressView() }
                    }
                }
                .disabled(link.state != .connected || installing)
                Button("New key", systemImage: "arrow.triangle.2.circlepath") { confirmReplace = true }
                Button("Delete key", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } else {
                Button("Generate SSH key", systemImage: "key") { generate() }
            }
        } header: {
            Text("SSH key")
        } footer: {
            Text(status ?? footer)
        }
        .confirmationDialog("Replace the SSH key?", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Replace key", role: .destructive) { generate() }
        } message: {
            Text("Macs that have the old key stop accepting it. Add the new key to them after this.")
        }
        .confirmationDialog("Delete the SSH key?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete key", role: .destructive) {
                DeviceKey.delete()
                publicLine = nil
                status = nil
            }
        } message: {
            Text("The app then logs in with a password only. The old line stays in authorized_keys on the Mac until you remove it.")
        }
    }

    private var footer: String {
        if publicLine == nil {
            return "An ed25519 key lets the app log in to the Mac without a password. The private key stays in this phone's Keychain."
        }
        if link.state != .connected {
            return "Connect in the Sessions tab to add the key to the Mac from here."
        }
        return "The app tries this key before the password."
    }

    private func generate() {
        do {
            publicLine = DeviceKey.publicLine(for: try DeviceKey.generate())
            status = nil
        } catch {
            status = error.localizedDescription
        }
    }

    private func install(_ line: String) async {
        installing = true
        defer { installing = false }
        do {
            _ = try await link.run(DeviceKey.installCommand(for: line))
            status = "Added to ~/.ssh/authorized_keys on \(link.host.hostname). The next login uses the key."
        } catch {
            status = "Could not add the key: \(SSHSession.message(for: error, host: link.host))"
        }
    }
}

private struct PasswordsSection: View {
    @AppStorage(SettingsKey.rememberPasswords) private var remember = true
    @State private var count = SavedPassword.count
    @State private var confirmForget = false

    var body: some View {
        Section {
            Toggle("Save passwords in Keychain", isOn: $remember)
            Button("Forget saved passwords", role: .destructive) { confirmForget = true }
                .disabled(count == 0)
        } header: {
            Text("Passwords")
        } footer: {
            Text(count == 0 ? "No saved passwords." : "\(count) saved password\(count == 1 ? "" : "s"). They stay on this phone and are not synced.")
        }
        .onAppear { count = SavedPassword.count }
        .confirmationDialog("Forget saved passwords?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget all", role: .destructive) {
                SavedPassword.removeAll()
                count = 0
            }
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }
}

#Preview {
    SettingsView()
        .environment(MacLink(host: AppStore.preview.hosts[0]))
        .preferredColorScheme(.dark)
}
