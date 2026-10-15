import SwiftUI

/// A terminal to open from this tab: the command it types, and the tmux session name for the status line.
struct SessionLaunch: Identifiable {
    let id = UUID()
    var command: String
    var title: String
}

struct SessionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(MacLink.self) private var link
    @State private var home: String?
    @State private var tmuxMissing = false
    @State private var loadError: String?
    @State private var loading = false
    @State private var showPicker = false
    @State private var launch: SessionLaunch?
    @State private var pendingKill: TmuxSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if link.state == .connected {
                        connectedContent
                    } else {
                        ConnectCard(link: link)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .refreshable { await refresh() }
            .background(Theme.background)
            .navigationTitle("Sessions")
            .toolbar {
                if link.state == .connected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("More", systemImage: "ellipsis.circle") {
                            Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                            Button("Disconnect", systemImage: "bolt.horizontal.circle") { link.disconnect() }
                        }
                    }
                }
            }
            .task(id: link.state) {
                if link.state == .connected { await refresh() }
            }
            .sheet(isPresented: $showPicker) {
                FolderPicker(link: link, sessions: store.sessions) { path in
                    showPicker = false
                    let name = Tmux.sessionName(for: path)
                    launch = SessionLaunch(command: Tmux.newClaudeCommand(name: name, path: path), title: name)
                }
            }
            .fullScreenCover(item: $launch, onDismiss: { Task { await refresh() } }) { launch in
                if let client = link.client {
                    TerminalScreen(host: link.host, client: client, command: launch.command, title: launch.title)
                }
            }
            .confirmationDialog(
                "Kill \(pendingKill?.name ?? "")?",
                isPresented: Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } }),
                titleVisibility: .visible,
                presenting: pendingKill
            ) { session in
                Button("Kill session", role: .destructive) { Task { await kill(session) } }
            } message: { _ in
                Text("Everything running in it stops, including Claude and dev servers.")
            }
        }
    }

    @ViewBuilder
    private var connectedContent: some View {
        NewClaudeSessionButton { showPicker = true }
            .padding(.bottom, 8)

        HStack {
            SectionLabel("tmux sessions")
            Spacer()
            if loading {
                ProgressView().controlSize(.small).tint(Theme.textTertiary)
            }
        }

        if tmuxMissing {
            NoticeCard(icon: "exclamationmark.triangle",
                       text: "tmux is not installed on the Mac. Run `brew install tmux` there, then refresh.")
        } else if let loadError {
            NoticeCard(icon: "exclamationmark.triangle", text: loadError)
        } else if store.sessions.isEmpty, !loading {
            Text("No sessions. Start one above.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .card()
        }

        ForEach(store.sessions) { session in
            SessionRow(session: session) {
                launch = SessionLaunch(command: Tmux.attachCommand(session.name), title: session.name)
            } onKill: {
                pendingKill = session
            }
        }
    }

    private func refresh() async {
        guard link.state == .connected else { return }
        loading = true
        defer { loading = false }
        do {
            let (home, result) = Tmux.parseList(try await link.run(Tmux.listCommand))
            self.home = home
            loadError = nil
            switch result {
            case .noTmux:
                tmuxMissing = true
                store.sessions = []
            case .sessions(let sessions):
                tmuxMissing = false
                store.sessions = sessions
            }
        } catch {
            loadError = "Could not list sessions: \(SSHSession.message(for: error, host: link.host))"
        }
    }

    private func kill(_ session: TmuxSession) async {
        pendingKill = nil
        do {
            _ = try await link.run(Tmux.killCommand(session.name))
        } catch {
            loadError = "Could not kill \(session.name): \(SSHSession.message(for: error, host: link.host))"
        }
        await refresh()
    }
}

/// Password prompt for the Sessions tab's connection.
struct ConnectCard: View {
    var link: MacLink
    @AppStorage(SettingsKey.sessionsAddress) private var address = ""
    @AppStorage(SettingsKey.rememberPasswords) private var remember = true
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatusDot(status: link.state == .connecting ? .unknown : .unreachable)
                TextField("user@host", text: $address)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .card()
            Text("Connect to see tmux sessions and start Claude in a repo.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            if case .failed(let message) = link.state {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SecureField("Password", text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit(connect)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .card()
            Button(action: connect) {
                Group {
                    if link.state == .connecting {
                        ProgressView()
                    } else {
                        Text("Connect")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canConnect)
            PasswordSaveToggle(remember: $remember)
        }
        .padding(16)
        .card()
        .onAppear {
            if address.isEmpty {
                address = link.host.address
            } else if let host = parsedHost {
                link.host = host
                link.connectSavedOnce()
            }
        }
    }

    private var parsedHost: Host? { Host(quickConnect: address) }

    /// An empty password still connects when the key or a saved password can log in.
    private var canConnect: Bool {
        guard let host = parsedHost, link.state != .connecting else { return false }
        return !password.isEmpty || Credentials.available(for: host)
    }

    private func connect() {
        guard canConnect, let host = parsedHost else { return }
        link.host = host
        link.connect(password: password.isEmpty ? nil : password, remember: remember)
        password = ""
    }
}

struct NoticeCard: View {
    var icon: String
    var text: String

    var body: some View {
        Label(LocalizedStringKey(text), systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .card()
    }
}

struct NewClaudeSessionButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Claude session")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Pick a repo and open Claude Code in tmux")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.25))
            )
        }
        .buttonStyle(.plain)
    }
}

struct SessionRow: View {
    var session: TmuxSession
    var onAttach: () -> Void = {}
    var onKill: () -> Void = {}

    var body: some View {
        Button(action: onAttach) {
            HStack(spacing: 14) {
                Image(systemName: "terminal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.name)
                            .font(.system(.headline, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                        if session.attached {
                            Text("attached")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.online)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.online.opacity(0.12), in: Capsule())
                        }
                    }
                    Text("\(session.path) · \(session.windows) window\(session.windows == 1 ? "" : "s")")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(session.created, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Attach", systemImage: "arrow.right.circle", action: onAttach)
            Button("Kill session", systemImage: "xmark.circle", role: .destructive, action: onKill)
        }
    }
}

#Preview {
    SessionsView()
        .environment(AppStore.preview)
        .environment(MacLink(host: AppStore.preview.hosts[0]))
        .preferredColorScheme(.dark)
}
