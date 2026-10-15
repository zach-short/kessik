import SwiftUI
import Citadel

/// Full-screen terminal for one host: password prompt, live shell, and clear error states.
struct TerminalScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.terminalFontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.rememberPasswords) private var remember = true
    @State private var session: SSHSession
    @State private var password = ""
    @FocusState private var passwordFocused: Bool
    private let title: String?

    init(host: Host) {
        _session = State(initialValue: SSHSession(host: host))
        title = nil
    }

    /// Opens a shell on an existing connection and types `command` into it. Closes when the shell ends.
    init(host: Host, client: SSHClient, command: String, title: String) {
        _session = State(initialValue: SSHSession(host: host, sharedClient: client, startCommand: command))
        self.title = title
    }

    var body: some View {
        VStack(spacing: 0) {
            statusLine
            ZStack {
                Theme.background
                TerminalHostView(session: session, fontSize: fontSize)
                    .opacity(session.state == .connected || session.state == .disconnected ? 1 : 0)
                overlay
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            if !session.ownsClient {
                session.start()
            } else if Credentials.available(for: session.host) {
                session.connect(password: nil)
            }
        }
        .onDisappear { session.disconnect() }
        .onChange(of: session.state) { _, state in
            // tmux detached or exited: go back to the session list.
            if state == .disconnected, !session.ownsClient { dismiss() }
        }
    }

    // MARK: Status line

    private var statusLine: some View {
        HStack(spacing: 10) {
            Button {
                session.disconnect()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.surfaceRaised, in: Circle())
            }
            .accessibilityLabel("Close")

            StatusDot(status: dotStatus)
            Text(session.host.address)
                .font(Theme.mono)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let title {
                Text(title)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
            Spacer()
            Text(stateLabel)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var dotStatus: Host.Status {
        switch session.state {
        case .connected: .online
        case .failed, .disconnected: .unreachable
        default: .unknown
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .needsPassword: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .failed: "Failed"
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlay: some View {
        switch session.state {
        case .needsPassword:
            passwordCard
        case .connecting:
            ProgressView()
                .controlSize(.large)
                .tint(Theme.textSecondary)
        case .failed(let message):
            messageCard(icon: "exclamationmark.triangle", title: "Could not connect", message: message)
        case .disconnected:
            VStack {
                Spacer()
                Button("Reconnect", systemImage: "arrow.clockwise") { session.reset() }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 24)
            }
        case .connected:
            EmptyView()
        }
    }

    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Password for \(session.host.username)")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .focused($passwordFocused)
                .submitLabel(.go)
                .onSubmit(connect)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .card()
            Button(action: connect) {
                Text("Connect").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(password.isEmpty)
            PasswordSaveToggle(remember: $remember)
        }
        .padding(20)
        .card()
        .padding(24)
        .onAppear { passwordFocused = true }
    }

    private func messageCard(icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if session.ownsClient {
                Button("Try again") { session.reset() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(24)
    }

    private func connect() {
        guard !password.isEmpty else { return }
        session.connect(password: password, remember: remember)
        password = ""
    }
}

/// "Save in Keychain" switch under a password field. The phone's key, when there is one, is tried first.
struct PasswordSaveToggle: View {
    @Binding var remember: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Save password in Keychain", isOn: $remember)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            if DeviceKey.load() != nil {
                Text("This phone's SSH key is tried first.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}
