import SwiftUI

/// Claude jobs the assistant handed off: working, waiting for you, done. Tap one to attach to its tmux session.
struct JobsView: View {
    @Environment(AppStore.self) private var store
    @Environment(MacLink.self) private var link
    @Environment(AssistantLink.self) private var assistant
    @AppStorage(SettingsKey.assistantUser) private var user = "agent"
    @State private var jobs: [Assistant.Job] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var launch: SessionLaunch?

    private var active: [Assistant.Job] { jobs.filter { ["approved", "started", "waiting"].contains($0.status) } }
    private var past: [Assistant.Job] { jobs.filter { !["approved", "started", "waiting"].contains($0.status) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error { InlineError(text: error) }
                if loaded, jobs.isEmpty {
                    Text("No jobs yet. Ask the assistant for code work, such as \"update the UI on ezhomesteading\", and approve the card.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(16)
                        .card()
                }
                if !active.isEmpty {
                    SectionLabel("Now")
                    ForEach(active) { job in row(job) }
                }
                if !past.isEmpty {
                    SectionLabel("Earlier").padding(.top, 8)
                    ForEach(past) { job in row(job) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Jobs")
        .refreshable { await load() }
        .task { await load() }
        .fullScreenCover(item: $launch, onDismiss: { Task { await load() } }) { launch in
            TerminalScreen(link: link, command: launch.command, title: launch.title, tmuxName: launch.tmuxName)
        }
    }

    private func row(_ job: Assistant.Job) -> some View {
        Button {
            launch = SessionLaunch(command: Tmux.attachCommand(job.session), title: job.session, tmuxName: job.session)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(job.repo)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    JobStatus(status: job.status)
                }
                Text(job.task)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Chip(text: "\(job.tier) · \(job.model)", icon: "cpu")
                    Chip(text: job.session, icon: "terminal")
                    Spacer()
                    Text(Assistant.shortTime(job.updatedAt))
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .card()
        }
        .buttonStyle(.plain)
        .disabled(job.status == "failed" || job.status == "approved")
    }

    private func load() async {
        guard let mac = store.activeMac else { return }
        do {
            jobs = try await assistant.call(AssistantReply.Jobs.self, to: mac, user: user, "jobs").jobs
            error = nil
        } catch {
            self.error = SSHSession.message(for: error, host: AssistantLink.host(for: mac, user: user))
        }
        loaded = true
    }
}
