import SwiftUI

/// Full-screen terminal for one host: password prompt, live shell, and clear error states.
struct TerminalScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.terminalFontSize) private var fontSize = 13.0
    @State private var session: SSHSession
    @State private var password = ""
    @FocusState private var passwordFocused: Bool

    init(host: Host) {
        _session = State(initialValue: SSHSession(host: host))
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
        .onDisappear { session.disconnect() }
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
            Text("The password is not saved.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
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
            Button("Try again") { session.reset() }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(24)
    }

    private func connect() {
        guard !password.isEmpty else { return }
        session.connect(password: password)
        password = ""
    }
}
