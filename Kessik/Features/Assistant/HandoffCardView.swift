import SwiftUI

/// A coding task the assistant wants to hand to Claude. It shows the exact text Claude will get, the repo
/// and the model, and starts nothing until Approve. Warnings flag text that looks personal.
struct HandoffCardView: View {
    var card: Assistant.Card
    var busy: Bool
    var onApprove: () -> Void
    var onEdit: () -> Void
    var onReject: () -> Void
    var onOpen: () -> Void

    private var model: String {
        Assistant.tiers.first { $0.name == card.tier }?.model ?? card.tier.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "hammer.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AssistantStyle.accent)
                    .frame(width: 34, height: 34)
                    .background(AssistantStyle.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hand off to Claude")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Job \(card.id)")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                JobStatus(status: card.status)
            }

            HStack(spacing: 6) {
                Chip(text: card.repo, icon: "folder")
                Chip(text: "\(card.tier) · \(model)", icon: "cpu")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Claude gets exactly this")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(card.task)
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            ForEach(card.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.shield")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }

            switch card.status {
            case "proposed":
                VStack(spacing: 8) {
                    Button(action: onApprove) {
                        if busy { ProgressView().tint(.white) } else { Text("Approve and start") }
                    }
                    .buttonStyle(FilledButtonStyle())
                    .disabled(busy)
                    HStack(spacing: 8) {
                        Button("Edit", action: onEdit).buttonStyle(QuietButtonStyle())
                        Button("Not now", action: onReject).buttonStyle(QuietButtonStyle())
                    }
                    .disabled(busy)
                }
            case "rejected":
                EmptyView()
            default:
                Button(action: onOpen) {
                    Label("Open terminal", systemImage: "terminal")
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: AssistantStyle.bigCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AssistantStyle.bigCorner, style: .continuous)
            .strokeBorder(card.status == "proposed" ? AssistantStyle.accent.opacity(0.5) : Theme.stroke))
    }
}

/// Edit a card's task and tier before approving it.
struct CardEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    var card: Assistant.Card
    var onApprove: (_ task: String, _ tier: String) -> Void
    @State private var task: String
    @State private var tier: String

    init(card: Assistant.Card, onApprove: @escaping (_ task: String, _ tier: String) -> Void) {
        self.card = card
        self.onApprove = onApprove
        _task = State(initialValue: card.task)
        _tier = State(initialValue: card.tier)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $task)
                        .frame(minHeight: 160)
                } header: {
                    Text("Task for Claude")
                } footer: {
                    Text("Claude gets this text and nothing else. Keep it to the coding work.")
                }
                Section("Model") {
                    Picker("Tier", selection: $tier) {
                        ForEach(Assistant.tiers, id: \.name) { t in
                            VStack(alignment: .leading) {
                                Text("\(t.name) · \(t.model)")
                                Text(t.note).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            .tag(t.name)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    LabeledContent("Repo", value: card.repo)
                }
            }
            .navigationTitle("Edit job \(card.id)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Approve") { onApprove(task, tier) }
                        .disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                }
            }
        }
    }
}
