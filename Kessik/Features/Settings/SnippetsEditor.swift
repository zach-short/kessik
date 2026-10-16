import SwiftUI

/// Add, edit, delete and reorder snippets. Replies and commands are separate lists.
struct SnippetsEditor: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Snippet?

    var body: some View {
        List {
            ForEach(Snippet.Kind.allCases) { kind in
                Section {
                    ForEach(store.snippets(kind)) { snippet in
                        Button { editing = snippet } label: { row(snippet) }
                    }
                    .onDelete { offsets in
                        let list = store.snippets(kind)
                        offsets.map { list[$0] }.forEach(store.delete)
                    }
                    .onMove { store.move(kind, from: $0, to: $1) }

                    Button("Add \(kind.title.lowercased())", systemImage: "plus") {
                        editing = Snippet(label: "", text: "", kind: kind)
                    }
                } header: {
                    Text(kind.listTitle)
                } footer: {
                    Text(kind.footer)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Snippets")
        .toolbar { EditButton() }
        .sheet(item: $editing) { snippet in
            SnippetForm(snippet: snippet, isNew: !store.snippets.contains { $0.id == snippet.id })
        }
    }

    private func row(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snippet.label)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(snippet.text)
                .font(Theme.mono)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct SnippetForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var snippet: Snippet
    @State private var confirmDelete = false
    private let isNew: Bool

    init(snippet: Snippet, isNew: Bool) {
        _snippet = State(initialValue: snippet)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $snippet.label, prompt: Text(trimmedText.isEmpty ? "Label" : trimmedText))
                    ShellTextField(text: $snippet.text, prompt: snippet.kind.prompt)
                }

                Section {
                    Picker("Kind", selection: $snippet.kind) {
                        ForEach(Snippet.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(snippet.kind.footer)
                }

                if !isNew {
                    Section {
                        Button("Delete snippet", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isNew ? "New snippet" : "Edit snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedText.isEmpty)
                }
            }
            .confirmationDialog("Delete \(snippet.label)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete snippet", role: .destructive) {
                    store.delete(snippet)
                    dismiss()
                }
            }
        }
    }

    /// A trailing new line would send an extra Return.
    private var trimmedText: String { snippet.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        var saved = snippet
        saved.text = trimmedText
        let label = snippet.label.trimmingCharacters(in: .whitespaces)
        saved.label = label.isEmpty ? trimmedText : label
        store.save(saved)
        dismiss()
    }
}

private extension Snippet.Kind {
    var listTitle: String {
        switch self {
        case .reply: "Replies"
        case .command: "Commands"
        }
    }

    var prompt: String {
        switch self {
        case .reply: "continue"
        case .command: "tmux new -A -s app -c ~/Projects/app claude"
        }
    }

    var footer: String {
        switch self {
        case .reply: "Replies show above the terminal. One tap types the text and Return into the open shell or Claude session."
        case .command: "Commands show in the Sessions tab. The app asks first, then runs the command in a new terminal on the Mac."
        }
    }
}
