import SwiftUI

enum SettingsKey {
    static let terminalFontSize = "terminalFontSize"
    /// Family name of the mono font. See `MonoFont`.
    static let monoFont = "monoFont"
    static let hapticsEnabled = "hapticsEnabled"
    /// Read once to move an address typed before Settings had a Mac section. See `SavedMac`.
    static let sessionsAddress = "sessionsAddress"
    static let rememberPasswords = "rememberPasswords"
    static let appearance = "appearance"
    /// The last port opened with Preview a port.
    static let previewPort = "previewPort"
    /// Id of the terminal palette. See `TerminalPalette`.
    static let terminalPalette = "terminalPalette"
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(SettingsKey.terminalFontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.monoFont) private var fontFamily = MonoFont.defaultFamily
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKey.appearance) private var appearance = AppAppearance.dark
    @AppStorage(SettingsKey.terminalPalette) private var paletteID = TerminalPalette.defaultID
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Form {
                MacsSection()

                Section {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    TerminalColorsPicker(paletteID: $paletteID) { PaletteSwatch(colors: $0) }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows the iOS light or dark setting. Default terminal colors follow the theme. The other terminal colors look the same on every theme.")
                }

                Section {
                    NavigationLink {
                        FontPicker()
                    } label: {
                        LabeledContent("Font", value: MonoFont.named(fontFamily).family)
                    }
                    NavigationLink("Key bar") { KeyBarEditor() }
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
                        .font(Font(MonoFont.named(fontFamily).uiFont(size: fontSize)))
                        .foregroundStyle(Theme.textPrimary)
                } header: {
                    Text("Terminal")
                } footer: {
                    Text("The font is also used for hostnames, paths and session names.")
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
                LoginLockSection()

                Section("Guides") {
                    ForEach(Guide.all) { guide in
                        NavigationLink {
                            GuideView(guide: guide, from: .settings)
                        } label: {
                            Label(guide.title, systemImage: guide.symbol)
                        }
                    }
                }

                Section {
                    HStack(spacing: 14) {
                        Image("AppMark")
                            .resizable()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kessik")
                                .font(.headline)
                            Text("Version \(Bundle.main.shortVersion)")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 2)
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

/// The palette's background with its text color and six ANSI colors on it.
private struct PaletteSwatch: View {
    let colors: TerminalPalette.Colors

    var body: some View {
        HStack(spacing: 2) {
            Text("A")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color(colors.foreground))
            ForEach(Array(colors.ansi.dropFirst().prefix(6).enumerated()), id: \.offset) { _, hex in
                Circle()
                    .fill(color(hex))
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 20)
        .background(color(colors.background), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.stroke))
        .accessibilityHidden(true)
    }

    private func color(_ hex: String) -> Color {
        let rgb = RGB8(hex: hex) ?? RGB8(red: 0, green: 0, blue: 0)
        return Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
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
