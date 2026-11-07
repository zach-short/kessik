import SwiftUI

/// Screens the Assistant tab pushes.
enum AssistantRoute: Hashable {
    case chat(Int?)
    case jobs
    case drafts
    case facts
}

/// The Assistant tab: a greeting, one big Ask card, quick actions and recent chats.
struct AssistantView: View {
    @Environment(AppStore.self) private var store
    @Environment(MacLink.self) private var link
    @Environment(AssistantLink.self) private var assistant
    @AppStorage(SettingsKey.assistantUser) private var user = "agent"
    @State private var path = NavigationPath()
    @State private var convs: [Assistant.Conversation] = []
    @State private var health: Assistant.Health?
    @State private var waitingJobs = 0
    @State private var error: String?
    @State private var loading = false
    @State private var showHealth = false
    @State private var confirmDigest = false
    @State private var toast: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let error { InlineError(text: error) }
                    askCard
                    actions
                    recent
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .refreshable { await refresh() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(AssistantRoute.chat(nil)) } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New chat")
                }
            }
            .navigationDestination(for: AssistantRoute.self) { route in
                switch route {
                case .chat(let id): ChatView(convID: id)
                case .jobs: JobsView()
                case .drafts: DraftsView()
                case .facts: FactsView()
                }
            }
            .task { await refresh() }
            .sheet(isPresented: $showHealth) { HealthSheet() }
            .confirmationDialog("Send the digest now?", isPresented: $confirmDigest, titleVisibility: .visible) {
                Button("Send digest") { Task { await sendDigest() } }
            } message: {
                Text("It goes to Telegram with counts only.")
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.greeting())
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                if loading { ProgressView().controlSize(.mini) }
            }
        }
        .padding(.top, 8)
    }

    private var askCard: some View {
        Button { path.append(AssistantRoute.chat(nil)) } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AssistantStyle.accent)
                    .frame(width: 44, height: 44)
                    .background(AssistantStyle.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask anything")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Questions stay on your Mac. Code work goes to Claude after you approve it.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                HStack {
                    Text("Start a chat")
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AssistantStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: AssistantStyle.bigCorner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AssistantStyle.bigCorner, style: .continuous).strokeBorder(Theme.stroke))
        }
        .buttonStyle(.plain)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Quick actions")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ActionTile(title: "Jobs", detail: jobsDetail, icon: "hammer", badge: waitingJobs) { path.append(AssistantRoute.jobs) }
                ActionTile(title: "Shadow drafts", detail: "Review mail drafts", icon: "envelope.open") { path.append(AssistantRoute.drafts) }
                ActionTile(title: "About me", detail: "What it knows", icon: "person.text.rectangle") { path.append(AssistantRoute.facts) }
                ActionTile(title: "Server health", detail: healthDetail, icon: "waveform.path.ecg") { showHealth = true }
                ActionTile(title: "Send digest", detail: "To Telegram now", icon: "paperplane") { confirmDigest = true }
            }
        }
    }

    @ViewBuilder
    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Recent chats")
            if convs.isEmpty {
                Text(loading ? "Loading…" : "No chats yet. Ask something to start one.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(convs.prefix(12).enumerated()), id: \.element.id) { index, conv in
                        if index > 0 { Divider().overlay(Theme.stroke).padding(.leading, 16) }
                        Button { path.append(AssistantRoute.chat(conv.id)) } label: {
                            ConversationRow(conv: conv)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()
            }
        }
    }

    // MARK: Status

    private var statusColor: Color {
        switch assistant.state {
        case .connected: health.map { $0.primaryModel ? Theme.online : Theme.warning } ?? Theme.online
        case .failed: Theme.warning
        default: Theme.offline
        }
    }

    private var statusText: String {
        if store.activeMac == nil { return "Add your Mac in Settings" }
        switch assistant.state {
        case .failed: return "Cannot reach the assistant"
        case .connecting: return "Connecting…"
        default:
            guard let health else { return "Your assistant" }
            return health.primaryModel ? "Mini online · local model ready" : "Mini online · model is loading"
        }
    }

    private var jobsDetail: String {
        waitingJobs > 0 ? "\(waitingJobs) waiting for you" : "Claude work"
    }

    private var healthDetail: String {
        guard let health else { return "Models and runs" }
        return health.loopMode == "live" ? "Mail loop live" : "Mail loop in shadow"
    }

    static func greeting(at date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: Requests

    private func refresh() async {
        guard let mac = store.activeMac else { return }
        loading = true
        defer { loading = false }
        await syncRepos(mac: mac)
        do {
            convs = try await assistant.call(AssistantReply.Convs.self, to: mac, user: user, "convs").convs
            let jobs = try await assistant.call(AssistantReply.Jobs.self, to: mac, user: user, "jobs").jobs
            waitingJobs = jobs.filter { $0.status == "waiting" }.count
            health = try? await assistant.call(AssistantReply.HealthReply.self, to: mac, user: user, "health").health
            error = nil
        } catch {
            self.error = SSHSession.message(for: error, host: AssistantLink.host(for: mac, user: user))
        }
    }

    /// Sends the repo list from the admin login, so the assistant knows names and folders but never
    /// reads the admin home itself. Skipped when the Sessions login is not open.
    private func syncRepos(mac: Host) async {
        guard link.state == .connected, let output = try? await link.run(JobStart.reposCommand),
              let parsed = JobStart.parseRepos(output) else { return }
        assistant.macHome = parsed.home
        _ = try? await assistant.call(AssistantReply.Repos.self, to: mac, user: user, "repos-set",
                                      payload: ["repos": parsed.repos])
    }

    private func sendDigest() async {
        guard let mac = store.activeMac else { return }
        do {
            let r = try await assistant.call(AssistantReply.Digest.self, to: mac, user: user, "digest")
            show(r.sent ? "Digest sent" : "The digest did not send")
        } catch {
            show(SSHSession.message(for: error, host: mac))
        }
    }

    private func show(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { toast = nil }
        }
    }
}

/// One tile in the quick actions grid.
struct ActionTile: View {
    var title: String
    var detail: String
    var icon: String
    var badge: Int = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AssistantStyle.accent)
                        .frame(width: 36, height: 36)
                        .background(AssistantStyle.accent.opacity(0.14), in: Circle())
                    Spacer()
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Theme.warning, in: Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card()
            .contentShape(RoundedRectangle(cornerRadius: Theme.corner))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct ConversationRow: View {
    var conv: Assistant.Conversation

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conv.title.isEmpty ? "Chat" : conv.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let last = conv.last, !last.isEmpty {
                    Text(last)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(Assistant.shortTime(conv.updatedAt))
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
