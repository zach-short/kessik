import SwiftUI

enum SettingsKey {
    static let terminalFontSize = "terminalFontSize"
    static let hapticsEnabled = "hapticsEnabled"
    /// Read once to move an address typed before Settings had a Mac section. See `SavedMac`.
    static let sessionsAddress = "sessionsAddress"
    static let rememberPasswords = "rememberPasswords"
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(SettingsKey.terminalFontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                MacSection()

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

                Section {
                    Toggle("Haptics on key taps", isOn: $hapticsEnabled)
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("For the key bar and reply chips. Letter keys follow iOS Settings > Sounds & Haptics > Keyboard Feedback.")
                }

                Section {
                    NavigationLink {
                        SnippetsEditor()
                    } label: {
                        LabeledContent("Snippets", value: "\(store.snippets.count)")
                    }
                } footer: {
                    Text("Saved replies and commands you run with one tap.")
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

/// Where the app logs in: name, hostname, port and username. Edits apply on Save, so typing
/// does not drop the connection on each key.
private struct MacSection: View {
    @Environment(AppStore.self) private var store
    @Environment(MacLink.self) private var link
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = ""
    @State private var username = ""
    @State private var savedNote = false

    var body: some View {
        Section {
            field("Name", prompt: "Mac", text: $name)
            field("Hostname", prompt: "mac.tailnet.ts.net", text: $hostname, keyboard: .URL)
            field("Port", prompt: "22", text: $port, keyboard: .numberPad)
            field("Username", prompt: "whoami on the Mac", text: $username)
            Button("Save") { save() }
                .disabled(draft == nil || !changed)
        } header: {
            Text("Mac")
        } footer: {
            Text(LocalizedStringKey(footer))
        }
        .onAppear(perform: load)
        .onChange(of: [name, hostname, port, username]) { savedNote = false }
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

    private var trimmedHostname: String { hostname.trimmingCharacters(in: .whitespaces) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespaces) }

    private var portNumber: Int? {
        let text = port.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return 22 }
        return Int(text).flatMap { (1...65535).contains($0) ? $0 : nil }
    }

    private var hostnameProblem: String? {
        if trimmedHostname.contains(where: \.isWhitespace) { return "The hostname cannot have spaces." }
        if trimmedHostname.contains("@") { return "Put the username in its own field." }
        return nil
    }

    /// The host to save, or nil while a field is empty or not valid.
    private var draft: Host? {
        guard !trimmedHostname.isEmpty, !trimmedUsername.isEmpty, hostnameProblem == nil,
              !trimmedUsername.contains(where: \.isWhitespace), let portNumber else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        var host = link.host.isSet ? link.host : Host.unset
        host.name = trimmedName.isEmpty ? "Mac" : trimmedName
        host.hostname = trimmedHostname
        host.port = portNumber
        host.username = trimmedUsername
        return host
    }

    private var changed: Bool {
        guard let draft else { return false }
        return !link.host.isSet || !draft.sameLogin(as: link.host) || draft.name != link.host.name
    }

    private var footer: String {
        if let hostnameProblem { return hostnameProblem }
        if portNumber == nil { return "The port is a number from 1 to 65535." }
        if savedNote { return "Saved. The Sessions tab uses this Mac." }
        if let draft, link.host.isSet, !draft.sameLogin(as: link.host), link.state == .connected {
            return "Saving disconnects from \(link.host.hostname) and closes its open terminals."
        }
        return "Use the Mac's Tailscale name or 100.x address. Run `whoami` on the Mac to get the username."
    }

    private func load() {
        let host = link.host
        name = host.isSet ? host.name : ""
        hostname = host.hostname
        port = host.isSet && host.port != 22 ? String(host.port) : ""
        username = host.username
    }

    private func save() {
        guard let host = draft else { return }
        SavedMac.save(host)
        store.hosts = [host]
        link.use(host)
        savedNote = true
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
        .environment(AppStore.preview)
        .environment(MacLink(host: AppStore.preview.hosts[0]))
        .preferredColorScheme(.dark)
}
