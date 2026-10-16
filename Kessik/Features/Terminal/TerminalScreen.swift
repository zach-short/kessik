import SwiftUI
import PhotosUI
import SafariServices
import SwiftTerm

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
    /// The user picked the Claude app before the terminal was ready. The pick runs once it connects.
    @State private var openClaudeWhenReady = false
    @FocusState private var passwordFocused: Bool
    @AppStorage(SettingsKey.previewPort) private var previewPort = 3000
    @State private var composing = false
    @State private var pickingImage = false
    @State private var pickedImage: PhotosPickerItem?
    @State private var askingPort = false
    @State private var portText = ""
    @State private var forward: PortForward?
    @State private var showPreview = false
    /// Shown in place of the state label while an upload or a forward starts.
    @State private var busy: String?
    @State private var toolError: String?
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
                TerminalHostView(session: session, fontSize: fontSize, watch: watch) { composing = true }
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
        .onDisappear {
            forward?.stop()
            session.disconnect()
        }
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
            if state == .connected, openClaudeWhenReady {
                openClaudeWhenReady = false
                RemoteControlCard.openClaude()
            }
        }
        .sheet(isPresented: $composing, onDismiss: refocusTerminal) {
            ComposeSheet { text, send in paste(text, send: send) }
        }
        .photosPicker(isPresented: $pickingImage, selection: $pickedImage, matching: .images)
        .onChange(of: pickedImage) { _, item in
            if let item { upload(item) }
            pickedImage = nil
        }
        .alert("Preview a port", isPresented: $askingPort) {
            TextField("Port", text: $portText)
                .keyboardType(.numberPad)
            Button("Open") { startPreview() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Opens a server that runs on the Mac, such as a dev server, in a browser on this phone.")
        }
        .alert("Could not finish", isPresented: Binding(get: { toolError != nil }, set: { if !$0 { toolError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(toolError ?? "")
        }
        .sheet(isPresented: $showPreview, onDismiss: refocusTerminal) {
            if let forward {
                SafariView(url: forward.url).ignoresSafeArea()
            }
        }
        .sheet(isPresented: remoteControlSheet) {
            if let title {
                RemoteControlCard(name: title) {
                    // Hold the pick until the terminal is ready, or run it now if it already is.
                    showRemoteControl = false
                    if session.state == .connected {
                        RemoteControlCard.openClaude()
                    } else {
                        openClaudeWhenReady = true
                    }
                } onStay: {
                    showRemoteControl = false
                }
            }
        }
    }

    /// The Remote Control sheet opens as soon as the terminal opens, and closes after the user picks.
    private var remoteControlSheet: Binding<Bool> {
        Binding(
            get: { showRemoteControl && title != nil },
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
            Text(busy ?? stateLabel)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            toolsMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Tools

    private var toolsMenu: some View {
        Menu {
            Button("Write a prompt", systemImage: "square.and.pencil") { composing = true }
            Button("Send an image", systemImage: "photo") { pickingImage = true }
            Button("Preview a port", systemImage: "safari") {
                portText = String(previewPort)
                askingPort = true
            }
            if let forward {
                Button("Stop port \(forward.remotePort)", systemImage: "xmark.circle") {
                    forward.stop()
                    self.forward = nil
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Theme.surfaceRaised, in: Circle())
        }
        .accessibilityLabel("Tools")
        .disabled(session.state != .connected || busy != nil)
    }

    /// The text goes in as one paste. Return, when asked for, follows after a pause, as for replies.
    private func paste(_ text: String, send: Bool) {
        watch.leaveHistory()
        let bracketed = watch.terminal?.getTerminal().bracketedPasteMode ?? false
        session.send(PasteText.bytes(text, bracketed: bracketed))
        guard send else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            session.send("\r")
        }
    }

    /// Puts the image on the Mac and types its path, so it can go into the prompt.
    private func upload(_ item: PhotosPickerItem) {
        guard let client = session.sshClient else { return }
        busy = "Uploading…"
        Task {
            defer { busy = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw ImageUpload.Unreadable() }
                let path = try await ImageUpload.upload(data, client: client)
                watch.leaveHistory()
                session.send(path + " ")
                refocusTerminal()
            } catch {
                toolError = (error as? LocalizedError)?.errorDescription ?? "The upload failed: \(error)"
            }
        }
    }

    private func startPreview() {
        guard let port = Int(portText.trimmingCharacters(in: .whitespaces)), (1...65535).contains(port) else {
            toolError = "Type a port number from 1 to 65535."
            return
        }
        guard let client = session.sshClient else { return }
        previewPort = port
        // One forward at a time: the same port opens the browser again on the open forward.
        if let forward, forward.remotePort == port {
            showPreview = true
            return
        }
        forward?.stop()
        forward = nil
        busy = "Opening port \(port)…"
        Task {
            defer { busy = nil }
            do {
                forward = try await PortForward.start(client: client, remotePort: port)
                showPreview = true
            } catch {
                toolError = (error as? LocalizedError)?.errorDescription ?? "The port could not open: \(error)"
            }
        }
    }

    private func refocusTerminal() {
        DispatchQueue.main.async { _ = watch.terminal?.becomeFirstResponder() }
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

/// Safari inside the app. The app stays in the foreground, so iOS keeps the port forward open.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
