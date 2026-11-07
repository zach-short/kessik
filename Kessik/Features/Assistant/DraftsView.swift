import SwiftUI

/// The mail loop's shadow drafts: what it would have saved in your mailbox. Mark each one good or bad;
/// the marks stay on the Mac and become test data for the mail router and the draft prompt.
struct DraftsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AssistantLink.self) private var assistant
    @AppStorage(SettingsKey.assistantUser) private var user = "agent"
    @State private var drafts: [Assistant.Draft] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var open: Assistant.Draft?

    private var toReview: Int { drafts.filter { $0.review == nil }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error { InlineError(text: error) }
                if loaded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(toReview)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text(toReview == 1 ? "draft to review" : "drafts to review")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
                if loaded, drafts.isEmpty {
                    Text("No shadow drafts yet. The mail loop saves one here when an email needs a reply.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(16)
                        .card()
                }
                ForEach(drafts) { draft in
                    Button { open = draft } label: { DraftRow(draft: draft) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Shadow drafts")
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $open) { draft in
            DraftReviewSheet(draft: draft) { verdict, classOK, note in
                open = nil
                Task { await mark(draft, verdict: verdict, classOK: classOK, note: note) }
            }
        }
    }

    private func load() async {
        guard let mac = store.activeMac else { return }
        do {
            drafts = try await assistant.call(AssistantReply.Drafts.self, to: mac, user: user, "drafts", [50]).drafts
            error = nil
        } catch {
            self.error = SSHSession.message(for: error, host: AssistantLink.host(for: mac, user: user))
        }
        loaded = true
    }

    private func mark(_ draft: Assistant.Draft, verdict: String, classOK: Bool?, note: String) async {
        guard let mac = store.activeMac else { return }
        var payload: [String: Any] = ["verdict": verdict, "note": note]
        payload["class_ok"] = classOK.map { $0 as Any } ?? NSNull()
        do {
            _ = try await assistant.call(AssistantReply.Empty.self, to: mac, user: user, "draft-mark", [draft.id], payload: payload)
            await load()
        } catch {
            self.error = SSHSession.message(for: error, host: AssistantLink.host(for: mac, user: user))
        }
    }
}

struct DraftRow: View {
    var draft: Assistant.Draft

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: draft.isEvent ? "calendar.badge.clock" : "envelope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AssistantStyle.accent)
                .frame(width: 34, height: 34)
                .background(AssistantStyle.accent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.subject.isEmpty ? "(no subject)" : draft.subject)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(Self.name(draft.sender))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text(draft.isEvent ? (draft.event?["title"] ?? "Held time") : draft.body)
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                Text(Assistant.shortTime(draft.createdAt))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                if let review = draft.review {
                    Image(systemName: review.verdict == "good" ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .foregroundStyle(review.verdict == "good" ? AssistantStyle.accent : Theme.accent)
                } else if draft.urgent {
                    Chip(text: "Urgent", color: Theme.warning)
                }
            }
        }
        .padding(14)
        .card()
    }

    /// `"Pat Lee" <pat@x.com>` → `Pat Lee`.
    static func name(_ sender: String) -> String {
        let trimmed = sender.components(separatedBy: "<").first?.trimmingCharacters(in: .whitespaces) ?? sender
        let name = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return name.isEmpty ? sender : name
    }
}

/// One draft in full, with the mail it answers, and the review controls.
struct DraftReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    var draft: Assistant.Draft
    var onMark: (_ verdict: String, _ classOK: Bool?, _ note: String) -> Void
    @State private var note: String
    @State private var classWrong: Bool

    init(draft: Assistant.Draft, onMark: @escaping (_ verdict: String, _ classOK: Bool?, _ note: String) -> Void) {
        self.draft = draft
        self.onMark = onMark
        _note = State(initialValue: draft.review?.note ?? "")
        _classWrong = State(initialValue: draft.review?.classOk == 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.subject.isEmpty ? "(no subject)" : draft.subject)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(draft.sender)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 6) {
                            if let account = draft.account { Chip(text: account, icon: "tray") }
                            if let cls = draft.classification { Chip(text: cls, icon: "tag") }
                        }
                        .padding(.top, 4)
                        if !draft.reason.isEmpty {
                            Text("Router: \(draft.reason)")
                                .font(.footnote)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.top, 2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(draft.isEvent ? "Held time" : "Draft reply")
                        Text(draft.isEvent ? eventText : draft.body)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .card()
                        if !draft.isEvent, draft.body.contains("[ZACH:") {
                            Label("Has a [ZACH: …] marker for you to fill in", systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Your review")
                        Toggle("The class was wrong", isOn: $classWrong)
                            .padding(14)
                            .card()
                        TextField("Note (optional): what was off?", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(14)
                            .card()
                    }

                    HStack(spacing: 10) {
                        Button { onMark("bad", !classWrong, note) } label: {
                            Label("Bad", systemImage: "hand.thumbsdown")
                        }
                        .buttonStyle(QuietButtonStyle())
                        Button { onMark("good", !classWrong, note) } label: {
                            Label("Good", systemImage: "hand.thumbsup")
                        }
                        .buttonStyle(FilledButtonStyle())
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private var eventText: String {
        let e = draft.event ?? [:]
        return [e["title"], e["start"], e["end"]].compactMap { $0 }.joined(separator: "\n")
    }
}
