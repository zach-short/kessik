import Foundation
import Observation
import SwiftUI

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
    /// Logged in to first, to reach the Mac through it. Nil connects straight to the Mac.
    /// Optional, so Macs saved before jump hosts still decode.
    var jump: JumpHost?
    /// Terminal colors for this Mac, by palette id. Nil uses the palette from Settings. Older
    /// builds saved no such key, and a missing key decodes as nil.
    var paletteID: String?
    /// Run in place of `claude --remote-control` when New session starts tmux, such as `codex`.
    /// Nil or blank keeps the default. Older builds saved no such key, and a missing key decodes as nil.
    var startCommand: String?

    var address: String { port == 22 ? "\(username)@\(hostname)" : "\(username)@\(hostname):\(port)" }

    /// No Mac set yet. The Sessions tab asks for one in Settings.
    static let unset = Host(name: "Mac", hostname: "", username: "")

    var isSet: Bool { !hostname.isEmpty && !username.isEmpty }

    /// The start command when one is set, trimmed. Nil runs Claude Code with Remote Control.
    var customStartCommand: String? {
        let command = startCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return command.isEmpty ? nil : command
    }

    /// Same login target: the Keychain password and host key belong to it.
    func sameLogin(as other: Host) -> Bool {
        hostname == other.hostname && port == other.port && username == other.username
    }
}

/// The saved Macs and the active one, which the Sessions tab and its terminals use. A plain value,
/// so the rules test without the app. `SavedMacs` stores it.
struct MacList: Equatable {
    private(set) var macs: [Host]
    private(set) var activeID: UUID?

    init(macs: [Host] = [], activeID: UUID? = nil) {
        self.macs = macs
        self.activeID = activeID
        settle()
    }

    var active: Host? { macs.first { $0.id == activeID } }

    /// Replaces the Mac with the same id, or adds it at the end. The first Mac becomes the active one.
    mutating func save(_ host: Host) {
        if let index = macs.firstIndex(where: { $0.id == host.id }) {
            macs[index] = host
        } else {
            macs.append(host)
        }
        settle()
    }

    mutating func remove(_ id: UUID) {
        macs.removeAll { $0.id == id }
        settle()
    }

    /// Does nothing for an id that is not in the list.
    mutating func setActive(_ id: UUID) {
        guard macs.contains(where: { $0.id == id }) else { return }
        activeID = id
    }

    /// Another saved Mac logs in to the same target, so the Keychain password and host key are still in use.
    func sharesLogin(with host: Host) -> Bool {
        macs.contains { $0.id != host.id && $0.sameLogin(as: host) }
    }

    /// Keeps the active id on a saved Mac. When the active Mac goes, the first one left takes its place.
    private mutating func settle() {
        if !macs.contains(where: { $0.id == activeID }) {
            activeID = macs.first?.id
        }
    }
}

/// Keeps the Mac list in UserDefaults. Passwords stay in the Keychain, keyed by login target, so the
/// list holds no secrets.
struct SavedMacs {
    static let listKey = "savedMacs"
    static let activeKey = "activeMac"
    /// The one Mac of earlier versions. It is moved into the list on first load and then kept equal
    /// to the active Mac, so an older build still finds a Mac.
    static let legacyKey = "savedMac"

    var defaults: UserDefaults = .standard

    func load() -> MacList {
        if let data = defaults.data(forKey: Self.listKey), let macs = try? JSONDecoder().decode([Host].self, from: data) {
            return MacList(macs: macs, activeID: defaults.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:)))
        }
        return migrate()
    }

    func save(_ list: MacList) {
        let macs = list.macs.map { host in
            var host = host
            host.status = .unknown
            return host
        }
        guard let data = try? JSONEncoder().encode(macs) else { return }
        defaults.set(data, forKey: Self.listKey)
        let active = macs.first { $0.id == list.activeID }
        if let active, let legacy = try? JSONEncoder().encode(active) {
            defaults.set(active.id.uuidString, forKey: Self.activeKey)
            defaults.set(legacy, forKey: Self.legacyKey)
        } else {
            defaults.removeObject(forKey: Self.activeKey)
            defaults.removeObject(forKey: Self.legacyKey)
        }
    }

    /// The Mac from `savedMac` becomes the first and active entry. Before Settings had a Mac section,
    /// the Sessions connect card kept a typed address instead.
    private func migrate() -> MacList {
        var list = MacList()
        if let data = defaults.data(forKey: Self.legacyKey), let host = try? JSONDecoder().decode(Host.self, from: data) {
            list.save(host)
        } else if let typed = defaults.string(forKey: SettingsKey.sessionsAddress), var host = Host(quickConnect: typed) {
            host.name = "Mac"
            list.save(host)
        }
        if !list.macs.isEmpty { save(list) }
        return list
    }
}

/// The active Mac, for code that uses one Mac. See `SavedMacs` for the whole list.
enum SavedMac {
    static func load() -> Host? {
        SavedMacs().load().active
    }

    /// Adds the Mac, or replaces the saved Mac with its id, and makes it the active one.
    static func save(_ host: Host) {
        let saved = SavedMacs()
        var list = saved.load()
        list.save(host)
        list.setActive(host.id)
        saved.save(list)
    }
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
    /// The saved Macs. Change them through `saveMac`, `useMac` and `removeMac`, which store each change.
    private(set) var macs: MacList
    var sessions: [TmuxSession]
    /// Kept grouped by kind, in the order Settings shows them. The app root saves each change.
    var snippets: [Snippet]
    /// Nil in previews, which keep their Macs in memory.
    private let savedMacs: SavedMacs?

    var hosts: [Host] { macs.macs }
    /// The Mac the Sessions tab and its terminals use.
    var activeMac: Host? { macs.active }

    init(hosts: [Host] = [], sessions: [TmuxSession] = [], snippets: [Snippet] = SavedSnippets.defaults,
         savedMacs: SavedMacs? = nil) {
        self.macs = savedMacs?.load() ?? MacList(macs: hosts)
        self.sessions = sessions
        self.snippets = snippets
        self.savedMacs = savedMacs
    }

    /// The Macs from Settings, or none on a fresh install. Sessions come from the Mac.
    convenience init() {
        self.init(sessions: [], snippets: SavedSnippets.load(), savedMacs: SavedMacs())
    }

    /// Adds a Mac or edits one. `activate` makes it the Mac the Sessions tab uses.
    func saveMac(_ host: Host, activate: Bool) {
        let old = hosts.first { $0.id == host.id }
        changeMacs {
            $0.save(host)
            if activate { $0.setActive(host.id) }
        }
        // A jump host this Mac no longer uses keeps no password, unless another Mac still logs in to it.
        if let oldJump = old?.jump?.login, host.jump.map({ !$0.login.sameLogin(as: oldJump) }) ?? true,
           !macs.macs.contains(where: { $0.sameLogin(as: oldJump) || $0.jump?.login.sameLogin(as: oldJump) == true }) {
            SavedPassword.remove(for: oldJump)
        }
    }

    func useMac(_ host: Host) {
        changeMacs { $0.setActive(host.id) }
    }

    /// Also forgets the Mac's saved password, unless another saved Mac logs in to the same target.
    func removeMac(_ host: Host) {
        changeMacs { $0.remove(host.id) }
        if !macs.sharesLogin(with: host), !macs.jumpsThrough(host) {
            SavedPassword.remove(for: host)
        }
        if let jump = host.jump, !macs.sharesJumpLogin(with: host) {
            SavedPassword.remove(for: jump.login)
        }
    }

    /// The session list belongs to the active Mac, so it empties when the active login changes.
    private func changeMacs(_ change: (inout MacList) -> Void) {
        let before = macs.active
        change(&macs)
        let sameLogin = before.flatMap { old in macs.active.map { old.sameLogin(as: $0) } } ?? false
        if !sameLogin { sessions = [] }
        savedMacs?.save(macs)
    }

    func snippets(_ kind: Snippet.Kind) -> [Snippet] {
        snippets.filter { $0.kind == kind }
    }

    /// Adds a new snippet at the end of its kind, or replaces the one with the same id.
    func save(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
        regroup()
    }

    func delete(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
    }

    /// Moves within one kind. `source` and `destination` index into `snippets(kind)`.
    func move(_ kind: Snippet.Kind, from source: IndexSet, to destination: Int) {
        var moved = snippets(kind)
        moved.move(fromOffsets: source, toOffset: destination)
        snippets = Snippet.Kind.allCases.flatMap { $0 == kind ? moved : snippets($0) }
    }

    private func regroup() {
        snippets = Snippet.Kind.allCases.flatMap(snippets)
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
        ],
        snippets: SavedSnippets.defaults + [
            Snippet(label: "Git glance", text: "git status --short && git worktree list", kind: .command),
        ]
    )
}
