import SwiftUI

/// Full-screen terminal for one host: password prompt, live shell, and clear error states.
struct TerminalScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppStore.self) private var store
    @AppStorage(SettingsKey.terminalFontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.rememberPasswords) private var remember = true
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @State private var session: SSHSession
    @State private var watch: ScreenWatch
    @State private var password = ""
    @State private var replyCount = 0
    @State private var typingReply = false
    /// A new Claude session starts with Remote Control on. This card points to the Claude app.
    @State private var showRemoteControl: Bool
    @FocusState private var passwordFocused: Bool
    private let title: String?
    private let tmuxName: String?

    init(host: Host) {
        let session = SSHSession(host: host)
        _session = State(initialValue: session)
        _watch = State(initialValue: ScreenWatch(session: session))
        _showRemoteControl = State(initialValue: false)
        title = nil
        tmuxName = nil
    }

    /// Opens a shell on the Sessions tab's connection and types `command` into it. A tmux command
    /// closes the terminal when tmux detaches, and after a drop Reconnect attaches to `tmuxName`
    /// again. `title` goes in the status line. `remoteControl` is true when `command` starts a
    /// Claude Code session with Remote Control on, and shows the card that points to the Claude app.
    init(link: MacLink, command: String, title: String, tmuxName: String?, remoteControl: Bool = false) {
        let session = SSHSession(link: link, startCommand: command, tmuxName: tmuxName)
        _session = State(initialValue: session)
        _watch = State(initialValue: ScreenWatch(session: session))
        _showRemoteControl = State(initialValue: remoteControl)
        self.title = title
        self.tmuxName = tmuxName
    }

    var body: some View {
        VStack(spacing: 0) {
            statusLine
            // While Claude Code asks a question, its options take the replies' place.
            if let menu = watch.menu, session.state == .connected {
                MenuOptionBar(menu: menu) { watch.choose($0) }
            } else if !store.snippets(.reply).isEmpty {
                replyBar
            }
            ZStack {
                Theme.background
                TerminalHostView(session: session, fontSize: fontSize, watch: watch)
                    .opacity(terminalOpacity)
                overlay
                if watch.inHistory, session.state == .connected {
                    LatestOutputButton { watch.leaveHistory() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.checkAlive() }
        }
        .onChange(of: NetworkMonitor.shared.changes) { session.checkAlive() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if UIApplication.shared.applicationState == .active { session.checkAlive() }
            }
        }
        .onChange(of: session.state) { _, state in
            // tmux detached or exited: go back to the session list.
            if state == .disconnected, !session.ownsClient { dismiss() }
        }
        .sheet(isPresented: remoteControlSheet) {
            if let title {
                RemoteControlCard(name: title) { showRemoteControl = false }
            }
        }
    }

    /// The Remote Control sheet opens once the shell connects, and closes after the user picks.
    private var remoteControlSheet: Binding<Bool> {
        Binding(
            get: { showRemoteControl && session.state == .connected && title != nil },
            set: { showRemoteControl = $0 }
        )
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

    // MARK: Replies

    /// One tap types a saved reply, such as "continue", into the shell or Claude session.
    private var replyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.snippets(.reply)) { snippet in
                    Button { type(snippet) } label: {
                        Text(snippet.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Theme.surfaceRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Types \(snippet.text) and Return")
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
        .disabled(session.state != .connected)
        .opacity(session.state == .connected ? 1 : 0.4)
        .sensoryFeedback(trigger: replyCount) { _, _ in hapticsEnabled ? .impact(weight: .light) : nil }
    }

    private func type(_ snippet: Snippet) {
        // A double tap would type the text twice before either Return.
        guard !typingReply else { return }
        typingReply = true
        watch.leaveHistory()
        session.send(snippet.text)
        replyCount += 1
        // Claude Code can read one burst of text as a paste, where Return adds a new line instead
        // of sending. A short pause makes Return a key press of its own.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            session.send("\r")
            typingReply = false
        }
    }

    private var dotStatus: Host.Status {
        switch session.state {
        case .connected: .online
        case .failed, .dropped, .disconnected: .unreachable
        default: .unknown
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .needsPassword: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .dropped: "Connection lost"
        case .failed: "Failed"
        }
    }

    /// The last screen stays visible, dimmed, behind the reconnect card.
    private var terminalOpacity: Double {
        switch session.state {
        case .connected, .disconnected: 1
        case .dropped: 0.3
        default: 0
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlay: some View {
        switch session.state {
        case .needsPassword:
            passwordCard
        case .connecting:
            VStack(spacing: 6) {
                ConnectingAnimation()
                Text("Connecting to \(session.host.address)…")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 24)
        case .failed(let message):
            messageCard(icon: "exclamationmark.triangle", title: "Could not connect", message: message,
                        retry: "Try again")
        case .dropped(let message):
            messageCard(icon: "wifi.exclamationmark", title: "Connection lost", message: message,
                        retry: tmuxName.map { "Reconnect to \($0)" } ?? "Reconnect")
        case .disconnected:
            VStack {
                Spacer()
                Button("Reconnect", systemImage: "arrow.clockwise") { session.reconnect() }
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

    private func messageCard(icon: String, title: String, message: String, retry: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: session.reconnect) {
                Label(retry, systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if session.ownsClient {
                Button("Enter password") { session.reset() }
                    .frame(maxWidth: .infinity)
            } else {
                Button("Close") { dismiss() }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
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
