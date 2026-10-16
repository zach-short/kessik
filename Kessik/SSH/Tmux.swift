import Foundation

/// Shell commands the app sends to the Mac, and parsers for their output.
enum Tmux {
    /// Non-login exec shells do not load Homebrew's PATH, so tmux would be missing.
    static let pathPrefix = #"export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; "#
    static let noTmuxMarker = "__SSHTERM_NO_TMUX__"

    /// First line is $HOME, then one line per session. tmux escapes tabs in its output, so the
    /// separator is `:`, which session names cannot hold. The path goes last because it can.
    static let listCommand = pathPrefix
        + #"echo "$HOME"; "#
        + "command -v tmux >/dev/null 2>&1 || { echo \(noTmuxMarker); exit 0; }; "
        + "tmux ls -F '#{session_windows}:#{session_attached}:#{session_created}:#{session_name}:#{session_path}' 2>/dev/null; "
        + "true"

    /// First line is $HOME, then the folders in ~/Projects, most recently changed first.
    static let projectsCommand = #"echo "$HOME"; cd "$HOME/Projects" 2>/dev/null && ls -1tp | grep '/$'; true"#

    static func killCommand(_ name: String) -> String {
        pathPrefix + "tmux kill-session -t \(quote("=" + name))"
    }

    /// Typed into an interactive shell. `exec` ends the shell when tmux detaches, so the terminal closes too.
    static func attachCommand(_ name: String) -> String {
        "exec tmux attach -t \(quote("=" + name))" + mouseOn(name)
    }

    /// `--remote-control` starts Claude Code with Remote Control on, named after the session, so the
    /// Claude app and claude.ai/code list it. tmux only runs `claude` when it creates the session;
    /// with `-A` on an existing session the flag is ignored and Remote Control stays as it was.
    /// A Mac's own start command goes to tmux as one quoted string, and tmux runs it with the shell.
    static func newClaudeCommand(name: String, path: String, startCommand: String? = nil) -> String {
        let run = startCommand.map(quote) ?? "claude --remote-control \(quote(name))"
        return "exec tmux new -A -s \(quote(name)) -c \(quote(path)) \(run)" + mouseOn(name)
    }

    /// Runs after the attach. With `mouse on`, a swipe on the phone scrolls tmux's history. It is a
    /// session option, so a Mac terminal on the same session gets it too; other sessions keep theirs.
    /// The target needs the trailing `:`, or tmux reads `=name` as a pane and finds no session.
    private static func mouseOn(_ name: String) -> String {
        #" \; set -t "# + quote("=" + name + ":") + " mouse on"
    }

    /// tmux does not allow `.` or `:` in session names. Keep it short and readable.
    static func sessionName(for path: String) -> String {
        let folder = (path as NSString).lastPathComponent.lowercased()
        let name = folder.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? String($0) : "-" }.joined()
        return name.isEmpty ? "claude" : name
    }

    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    enum ListResult {
        case noTmux
        case sessions([TmuxSession])
    }

    static func parseList(_ output: String) -> (home: String?, result: ListResult) {
        var lines = output.split(separator: "\n")
        let home = lines.isEmpty ? nil : String(lines.removeFirst())
        if output.contains(noTmuxMarker) { return (home, .noTmux) }
        let sessions = lines.compactMap { line -> TmuxSession? in
            let f = line.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 5, let windows = Int(f[0]), let attached = Int(f[1]), let created = TimeInterval(f[2]) else {
                return nil
            }
            return TmuxSession(name: f[3], path: tilde(f[4], home: home), windows: windows,
                               attached: attached > 0, created: Date(timeIntervalSince1970: created))
        }
        return (home, .sessions(sessions.sorted { $0.created > $1.created }))
    }

    struct Projects {
        var home: String
        var folders: [String]
    }

    static func parseProjects(_ output: String) -> Projects? {
        var lines = output.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else { return nil }
        let home = lines.removeFirst()
        let folders = lines.map { home + "/Projects/" + $0.dropLast() }
        return Projects(home: home, folders: folders)
    }

    /// `/Users/me/x` → `~/x`, for display.
    static func tilde(_ path: String, home: String?) -> String {
        guard let home, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// `~/x` → `/Users/me/x`, so the path can be quoted safely.
    static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }
}
