import Foundation
import Observation

struct Host: Identifiable, Codable, Hashable {
    enum Status: String, Codable {
        case online, unreachable, unknown
    }

    var id = UUID()
    var name: String
    var hostname: String
    var port: Int = 22
    var username: String
    var lastConnected: Date?
    var status: Status = .unknown

    var address: String { port == 22 ? "\(username)@\(hostname)" : "\(username)@\(hostname):\(port)" }
}

extension Host {
    /// Parses `user@host` or `user@host:port` from the command bar.
    init?(quickConnect text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "@", maxSplits: 1)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        var hostname = String(parts[1])
        var port = 22
        if let colon = hostname.lastIndex(of: ":"), let p = Int(hostname[hostname.index(after: colon)...]) {
            port = p
            hostname = String(hostname[..<colon])
        }
        self.init(name: hostname, hostname: hostname, port: port, username: String(parts[0]))
    }
}

/// A tmux session on the Mac, as reported by `tmux ls`.
struct TmuxSession: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var path: String
    var windows: Int
    var attached: Bool
    var created: Date
}

@Observable
final class AppStore {
    var hosts: [Host]
    var sessions: [TmuxSession]

    init(hosts: [Host] = [], sessions: [TmuxSession] = []) {
        self.hosts = hosts
        self.sessions = sessions
    }

    /// Placeholder data until SSH lands (build step 2).
    convenience init() {
        self.init(hosts: AppStore.preview.hosts, sessions: AppStore.preview.sessions)
    }

    static let preview = AppStore(
        hosts: [
            Host(name: "Mac", hostname: "mac.tailnet.ts.net", username: "user",
                 lastConnected: .now.addingTimeInterval(-60 * 42), status: .online),
            Host(name: "Mac (LAN)", hostname: "192.168.1.20", username: "user",
                 lastConnected: .now.addingTimeInterval(-60 * 60 * 26), status: .unreachable),
        ],
        sessions: [
            TmuxSession(name: "claude-app", path: "~/Projects/app", windows: 2, attached: false,
                        created: .now.addingTimeInterval(-60 * 90)),
            TmuxSession(name: "dev-server", path: "~/Projects/site", windows: 1, attached: true,
                        created: .now.addingTimeInterval(-60 * 60 * 5)),
        ]
    )
}
