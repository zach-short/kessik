import SwiftUI

/// "About me": every fact the assistant keeps, grouped by topic. Add, edit and delete them here.
/// They live only on the Mac, and only the local model reads them.
struct FactsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AssistantLink.self) private var assistant
    @AppStorage(SettingsKey.assistantUser) private var user = "agent"
    @State private var facts: [Assistant.Fact] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var editing: FactDraft?

    struct FactDraft: Identifiable {
        var id: Int?
        var text: String
        var topic: String
    }

    private var topics: [(String, [Assistant.Fact])] {
        Dictionary(grouping: facts) { $0.topic.isEmpty ? "General" : $0.topic.capitalized }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
            }
            Section {
                Text("Only the local model on your Mac reads these. Claude never gets them.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            if loaded, facts.isEmpty {
                Section {
                    Text("Nothing yet. Tell the assistant something to remember, or add a fact here.")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            ForEach(topics, id: \.0) { topic, items in
                Section(topic) {
                    ForEach(items) { fact in
                        Button { editing = FactDraft(id: fact.id, text: fact.text, topic: fact.topic) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(fact.text).foregroundStyle(Theme.textPrimary)
                                Text(fact.source == "chat" ? "From a chat · \(Assistant.shortTime(fact.updatedAt))" : "Added by you · \(Assistant.shortTime(fact.updatedAt))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { Task { await delete(fact) } }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("About me")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = FactDraft(id: nil, text: "", topic: "") } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a fact")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $editing) { draft in
            FactEditSheet(draft: draft) { saved in
                editing = nil
                Task { await save(saved) }
            }
        }
    }

    private func load() async {
        guard let mac = store.activeMac else { return }
        do {
            facts = try await assistant.call(AssistantReply.Facts.self, to: mac, user: user, "facts").facts
            error = nil
        } catch {
            self.error = SSHSession.message(for: error, host: AssistantLink.host(for: mac, user: user))
        }
        loaded = true
    }

    private func save(_ draft: FactDraft) async {
        guard let mac = store.activeMac else { return }
        let payload: [String: Any] = ["text": draft.text, "topic": draft.topic]
        do {
            if let id = draft.id {
                _ = try await assistant.call(AssistantReply.Empty.self, to: mac, user: user, "fact-edit", [id], payload: payload)
            } else {
                _ = try await assistant.call(AssistantReply.Added.self, to: mac, user: user, "fact-add", payload: payload)
            }
            await load()
        } catch {
            self.error = SSHSession.message(for: error, host: AssistantLink.host(for: mac, user: user))
        }
    }

    private func delete(_ fact: Assistant.Fact) async {
        guard let mac = store.activeMac else { return }
        do {
            _ = try await assistant.call(AssistantReply.Empty.self, to: mac, user: user, "fact-del", [fact.id])
            facts.removeAll { $0.id == fact.id }
        } catch {
            self.error = SSHSession.message(for: error, host: AssistantLink.host(for: mac, user: user))
        }
    }
}

struct FactEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: FactsView.FactDraft
    var onSave: (FactsView.FactDraft) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Zach's Lexus is a 2019 RX 350", text: $draft.text, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Fact")
                } footer: {
                    Text("One short sentence. Do not store passwords, card numbers or codes.")
                }
                Section("Topic") {
                    TextField("car, home, health, work", text: $draft.topic)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(draft.id == nil ? "New fact" : "Edit fact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(draft) }
                        .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
