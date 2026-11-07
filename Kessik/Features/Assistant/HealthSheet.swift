import SwiftUI

/// Server health at a glance: the two local models, the last mail run, load and disk.
struct HealthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(AssistantLink.self) private var assistant
    @AppStorage(SettingsKey.assistantUser) private var user = "agent"
    @State private var health: Assistant.Health?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
                if let h = health {
                    Section("Local models") {
                        row("Primary (Qwen)", ok: h.primaryModel)
                        row("Router (Gemma)", ok: h.routerModel)
                    }
                    Section("Mail loop") {
                        LabeledContent("Mode", value: h.loopMode == "live" ? "Live" : "Shadow")
                        if let run = h.lastRun {
                            LabeledContent("Last run", value: run.finishedAt.map(Assistant.shortTime) ?? "running")
                            LabeledContent("Drafts", value: "\(run.drafts ?? 0)")
                            LabeledContent("Errors", value: "\(run.errors ?? 0)")
                            if let skipped = run.skipped, !skipped.isEmpty {
                                LabeledContent("Skipped", value: skipped.joined(separator: ", "))
                            }
                        }
                    }
                    Section("Mac") {
                        LabeledContent("Load", value: h.load.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                        LabeledContent("Free disk", value: "\(h.diskFreeGb) GB")
                        if let up = h.uptimeHours { LabeledContent("Up", value: up >= 48 ? "\(Int(up / 24)) days" : "\(Int(up)) hours") }
                        LabeledContent("Jobs running", value: "\(h.jobsRunning)")
                    }
                } else if error == nil {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .navigationTitle("Server health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, ok: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Label(ok ? "Ready" : "Down", systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(ok ? AssistantStyle.accent : Theme.accent)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func load() async {
        guard let mac = store.activeMac else { return }
        do {
            health = try await assistant.call(AssistantReply.HealthReply.self, to: mac, user: user, "health").health
            error = nil
        } catch {
            self.error = SSHSession.message(for: error, host: AssistantLink.host(for: mac, user: user))
        }
    }
}
