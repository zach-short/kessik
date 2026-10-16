import Foundation

/// Saved text the user runs with one tap.
struct Snippet: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// A chip above the terminal. Types the text and Return into the open shell or Claude session.
        case reply
        /// A row in the Sessions tab. Asks first, then opens a terminal on the Mac that runs it.
        case command

        var id: String { rawValue }

        var title: String {
            switch self {
            case .reply: "Reply"
            case .command: "Command"
            }
        }
    }

    var id = UUID()
    var label: String
    var text: String
    var kind: Kind
}

/// Snippets live in UserDefaults on this phone. Personal commands are added in Settings, not in code.
enum SavedSnippets {
    private static let key = "snippets"

    /// The most common replies in Claude Code sessions, from the transcript scan in docs/shortcut-candidates.md.
    static let defaults: [Snippet] = [
        Snippet(label: "Continue", text: "continue", kind: .reply),
        Snippet(label: "Yes", text: "yes", kind: .reply),
        Snippet(label: "Commit this", text: "commit this", kind: .reply),
        Snippet(label: "What's next", text: "whats next", kind: .reply),
        Snippet(label: "Delegate next", text: "delegate next item in passoff", kind: .reply),
        Snippet(label: "/usage", text: "/usage", kind: .reply),
    ]

    static func load() -> [Snippet] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snippets = try? JSONDecoder().decode([Snippet].self, from: data) else { return defaults }
        return snippets
    }

    static func save(_ snippets: [Snippet]) {
        if let data = try? JSONEncoder().encode(snippets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
