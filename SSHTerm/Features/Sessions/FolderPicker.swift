import SwiftUI

/// Lists the folders in ~/Projects on the Mac, newest first. Typing a path that starts with `~` or `/` uses it as is.
struct FolderPicker: View {
    var link: MacLink
    var sessions: [TmuxSession]
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var projects: Tmux.Projects?
    @State private var query = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let typedPath {
                    Section {
                        Button { onPick(typedPath) } label: {
                            Label("Open \(query)", systemImage: "folder.badge.plus")
                                .font(Theme.mono)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.warning)
                    } else if projects == nil {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if filtered.isEmpty {
                        Text(query.isEmpty ? "No folders in ~/Projects." : "No match.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(filtered, id: \.self) { path in
                        Button { onPick(path) } label: { row(path) }
                    }
                } header: {
                    Text("~/Projects")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter, or type a path")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Open Claude in…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
        .presentationDetents([.large])
    }

    private func row(_ path: String) -> some View {
        let name = Tmux.sessionName(for: path)
        let running = sessions.contains { $0.name == name }
        return HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(Theme.textSecondary)
            Text((path as NSString).lastPathComponent)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if running {
                Text("running")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.online)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.online.opacity(0.12), in: Capsule())
            }
        }
        .contentShape(Rectangle())
    }

    private var filtered: [String] {
        guard let projects else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, typedPath == nil else { return projects.folders }
        return projects.folders.filter { ($0 as NSString).lastPathComponent.localizedCaseInsensitiveContains(q) }
    }

    /// The query as an absolute path, when it looks like one.
    private var typedPath: String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let home = projects?.home, q.hasPrefix("/") || q.hasPrefix("~") else { return nil }
        let path = Tmux.expand(q, home: home)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func load() async {
        do {
            let output = try await link.run(Tmux.projectsCommand)
            projects = Tmux.parseProjects(output)
            if projects == nil { error = "The Mac returned no home folder." }
        } catch {
            self.error = SSHSession.message(for: error, host: link.host)
        }
    }
}
