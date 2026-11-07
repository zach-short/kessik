import SwiftUI

/// One chat with the assistant. The reply is made on the Mac by the local model; the app sends the
/// message, then asks for new messages until the turn ends. Dictation works from the keyboard's mic.
struct ChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(MacLink.self) private var link
    @Environment(AssistantLink.self) private var assistant
    @AppStorage(SettingsKey.assistantUser) private var user = "agent"
    @State var convID: Int?
    @State private var messages: [Assistant.Message] = []
    @State private var text = ""
    @State private var thinking = false
    @State private var error: String?
    @State private var editing: Assistant.Card?
    @State private var busyCard: Int?
    @State private var launch: SessionLaunch?
    @State private var confirmDelete = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(convID: Int?) {
        _convID = State(initialValue: convID)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty, !thinking { starter }
                    ForEach(messages) { message in
                        row(message).id(message.id)
                    }
                    if thinking { TypingBubble().id("typing") }
                    if let error { InlineError(text: error) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { scrollDown(proxy) }
            .onChange(of: thinking) { scrollDown(proxy) }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if convID != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Delete chat", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                }
            }
        }
        .confirmationDialog("Delete this chat?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete chat", role: .destructive) { Task { await deleteChat() } }
        } message: {
            Text("It is removed from the Mac. Facts the assistant saved stay in About me.")
        }
        .task { await load() }
        .sheet(item: $editing) { card in
            CardEditSheet(card: card) { task, tier in
                editing = nil
                Task { await approve(card, edits: ["task": task, "tier": tier]) }
            }
        }
        .fullScreenCover(item: $launch) { launch in
            TerminalScreen(link: link, command: launch.command, title: launch.title, tmuxName: launch.tmuxName)
        }
    }

    private var title: String {
        guard let first = messages.first(where: \.isUser)?.text else { return "New chat" }
        return String(first.prefix(40))
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ message: Assistant.Message) -> some View {
        if let card = message.card {
            HandoffCardView(card: card, busy: busyCard == card.id,
                            onApprove: { Task { await approve(card, edits: nil) } },
                            onEdit: { editing = card },
                            onReject: { Task { await reject(card) } },
                            onOpen: { open(job: card.id) })
        } else if message.role == "user" || message.role == "assistant" {
            Bubble(text: message.text, mine: message.isUser)
        }
    }

    private var starter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try asking")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            ForEach(["When was my last oil change?", "What is on my calendar tomorrow?", "Remember that my gym closes at 10 pm",
                     "Update the settings screen in kessik"], id: \.self) { sample in
                Button {
                    text = sample
                    focused = true
                } label: {
                    Text(sample)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .card()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(canSend ? AssistantStyle.accent : Theme.offline, in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !thinking && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scrollDown(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if thinking { proxy.scrollTo("typing", anchor: .bottom) } else if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    // MARK: Requests

    private func load() async {
        guard let mac = store.activeMac, let convID else { return }
        do {
            let r = try await assistant.call(AssistantReply.Conv.self, to: mac, user: user, "conv", [convID])
            messages = r.messages
            if r.turn?.isRunning == true { thinking = true; await poll(mac: mac, conv: convID) }
            error = nil
        } catch {
            self.error = describe(error, mac)
        }
    }

    private func send() async {
        guard let mac = store.activeMac else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        text = ""
        thinking = true
        error = nil
        do {
            var payload: [String: Any] = ["text": body]
            if let convID { payload["conv"] = convID }
            let sent = try await assistant.call(AssistantReply.Sent.self, to: mac, user: user, "send", payload: payload)
            convID = sent.conv
            await poll(mac: mac, conv: sent.conv)
        } catch {
            text = body
            thinking = false
            self.error = describe(error, mac)
        }
    }

    /// Asks for new messages every 1.5 seconds until the turn ends, for up to 10 minutes.
    private func poll(mac: Host, conv: Int) async {
        defer { thinking = false }
        let start = Date.now
        var misses = 0
        while !Task.isCancelled, Date.now.timeIntervalSince(start) < 600 {
            do {
                let r = try await assistant.call(AssistantReply.Conv.self, to: mac, user: user, "conv", [conv, messages.last?.id ?? 0])
                messages.append(contentsOf: r.messages.filter { m in !messages.contains { $0.id == m.id } })
                misses = 0
                if r.turn?.isRunning != true { return }
            } catch {
                misses += 1
                if misses >= 3 { self.error = describe(error, mac); return }
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    private func reload(card id: Int) async {
        guard let mac = store.activeMac, let convID,
              let r = try? await assistant.call(AssistantReply.Conv.self, to: mac, user: user, "conv", [convID]) else { return }
        messages = r.messages
    }

    /// Approve, then start the job in tmux over the admin login. The assistant's user sends only fields;
    /// `JobStart` checks them and builds the command here.
    private func approve(_ card: Assistant.Card, edits: [String: Any]?) async {
        guard let mac = store.activeMac else { return }
        busyCard = card.id
        defer { busyCard = nil }
        do {
            let job = try await assistant.call(AssistantReply.Approved.self, to: mac, user: user, "card-approve", [card.id], payload: edits).job
            let ok: Bool
            var note = ""
            do {
                try await start(job)
                ok = true
            } catch {
                ok = false
                note = describe(error, mac)
                self.error = note
            }
            _ = try? await assistant.call(AssistantReply.Empty.self, to: mac, user: user, "card-started", [card.id],
                                          payload: ["ok": ok, "note": note])
            await reload(card: card.id)
        } catch {
            self.error = describe(error, mac)
        }
    }

    private func start(_ job: Assistant.JobSpec) async throws {
        _ = try await link.ensureConnected()
        if assistant.macHome == nil, let output = try? await link.run(JobStart.reposCommand) {
            assistant.macHome = JobStart.parseRepos(output)?.home
        }
        let arguments = try JobStart.claudeArguments(for: job, home: assistant.macHome ?? "")
        let output = try await link.run(Tmux.startDetachedCommand(name: job.session, path: job.path, claudeArguments: arguments))
        switch Tmux.parseStart(output) {
        case .started, .alreadyRunning: break
        case .needsTrust: open(job: job.id)   // Claude Code asks to trust a new folder; only a person can answer
        case .exitedAtOnce: throw JobStart.Rejected(reason: "Claude Code ended as soon as it started")
        case .noTmux: throw JobStart.Rejected(reason: "tmux is not installed on the Mac")
        case nil: throw JobStart.Rejected(reason: "the Mac did not say whether it started")
        }
    }

    private func reject(_ card: Assistant.Card) async {
        guard let mac = store.activeMac else { return }
        busyCard = card.id
        defer { busyCard = nil }
        do {
            _ = try await assistant.call(AssistantReply.Empty.self, to: mac, user: user, "card-reject", [card.id])
            await reload(card: card.id)
        } catch {
            self.error = describe(error, mac)
        }
    }

    private func open(job id: Int) {
        let name = "job-\(id)"
        launch = SessionLaunch(command: Tmux.attachCommand(name), title: name, tmuxName: name)
    }

    private func deleteChat() async {
        guard let mac = store.activeMac, let convID else { return }
        do {
            _ = try await assistant.call(AssistantReply.Empty.self, to: mac, user: user, "delete-conv", [convID])
            dismiss()
        } catch {
            self.error = describe(error, mac)
        }
    }

    private func describe(_ error: Error, _ mac: Host) -> String {
        SSHSession.message(for: error, host: AssistantLink.host(for: mac, user: user))
    }
}

/// A chat bubble. Yours are filled and on the right; the assistant's sit on a card on the left.
struct Bubble: View {
    var text: String
    var mine: Bool

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 48) }
            Text(LocalizedStringKey(text))
                .font(.body)
                .foregroundStyle(mine ? .white : Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(mine ? AssistantStyle.accent : Theme.surface,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    if !mine { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke) }
                }
            if !mine { Spacer(minLength: 48) }
        }
    }
}

/// Three dots while the local model works.
struct TypingBubble: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.textTertiary)
                    .frame(width: 7, height: 7)
                    .opacity(phase == i ? 1 : 0.35)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeInOut(duration: 0.2)) { phase = (phase + 1) % 3 }
            }
        }
        .accessibilityLabel("The assistant is answering")
    }
}
