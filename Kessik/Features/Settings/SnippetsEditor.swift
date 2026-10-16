import SwiftUI
import UniformTypeIdentifiers

/// Add, edit, delete and reorder snippets. Replies and commands are separate lists.
/// Export and Import move them to another phone as a file.
struct SnippetsEditor: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Snippet?
    @State private var importing = false
    @State private var picked: [Snippet]?
    @State private var notice: Notice?

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Export or import", systemImage: "arrow.up.arrow.down.circle") {
                    ShareLink(item: SnippetsFile(snippets: store.snippets),
                              preview: SharePreview(SnippetTransfer.fileName)) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Button("Import", systemImage: "square.and.arrow.down") { importing = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(item: $editing) { snippet in
            SnippetForm(snippet: snippet, isNew: !store.snippets.contains { $0.id == snippet.id })
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            open(result)
        }
        .confirmationDialog(importTitle, isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }),
                            titleVisibility: .visible) {
            Button("Add to my snippets") { apply(.merge) }
            Button("Replace my snippets", role: .destructive) { apply(.replace) }
        } message: {
            Text("Add keeps your snippets and skips exact copies. Replace removes your snippets first.")
        }
        .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice?.message ?? "")
        }
    }

    private struct Notice {
        var title: String
        var message: String
    }

    private var importTitle: String {
        let count = picked?.count ?? 0
        return count == 1 ? "Import 1 snippet" : "Import \(count) snippets"
    }

    private func open(_ result: Result<URL, Error>) {
        do {
            picked = try SnippetTransfer.read(try result.get())
        } catch {
            notice = Notice(title: "Could not import", message: error.localizedDescription)
        }
    }

    private func apply(_ mode: SnippetTransfer.Mode) {
        guard let picked else { return }
        let before = store.snippets.count
        store.snippets = SnippetTransfer.combine(store.snippets, with: picked, mode: mode)
        let added = mode == .merge ? store.snippets.count - before : store.snippets.count
        let skipped = picked.count - added
        notice = Notice(title: "Imported",
                        message: skipped == 0 ? "Added \(added)." : "Added \(added). Skipped \(skipped) that you already have.")
        self.picked = nil
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

/// The export file. It holds only label, text and kind, from `SnippetTransfer`.
private struct SnippetsFile: Transferable {
    var snippets: [Snippet]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { try SnippetTransfer.encode($0.snippets) }
            .suggestedFileName(SnippetTransfer.fileName)
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
