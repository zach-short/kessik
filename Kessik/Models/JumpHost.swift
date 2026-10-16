import Foundation

/// A host the app logs in to first, to reach a Mac the phone cannot reach on its own, like
/// `ssh -J`. The Mac's hostname is then the name the jump host uses for it.
struct JumpHost: Codable, Hashable {
    var hostname: String
    var port: Int = 22
    var username: String

    var address: String { port == 22 ? "\(username)@\(hostname)" : "\(username)@\(hostname):\(port)" }

    /// The jump host as a login target. Its saved password and host key belong to it, as a Mac's do.
    var login: Host { Host(name: hostname, hostname: hostname, port: port, username: username) }
}

extension MacList {
    /// Another saved Mac uses the jump host login, so its Keychain password is still in use.
    func sharesJumpLogin(with host: Host) -> Bool {
        guard let jump = host.jump?.login else { return false }
        return macs.contains { $0.id != host.id && ($0.jump?.login.sameLogin(as: jump) == true || $0.sameLogin(as: jump)) }
    }

    /// Another saved Mac uses `host`'s login as its jump host.
    func jumpsThrough(_ host: Host) -> Bool {
        macs.contains { $0.id != host.id && $0.jump?.login.sameLogin(as: host) == true }
    }
}

/// The jump host fields of the Mac form, as typed. An empty hostname means no jump host.
struct JumpHostDraft: Equatable {
    enum Result: Equatable {
        case none
        case jump(JumpHost)
        /// A field is not valid. The text says which.
        case problem(String)
    }

    var hostname = ""
    var port = ""
    var username = ""
    /// Saved in the Keychain for the jump host on Save. Empty keeps the saved one.
    var password = ""

    init() {}

    init(_ jump: JumpHost?) {
        guard let jump else { return }
        hostname = jump.hostname
        port = jump.port == 22 ? "" : String(jump.port)
        username = jump.username
    }

    var result: Result {
        let host = hostname.trimmingCharacters(in: .whitespaces)
        let user = username.trimmingCharacters(in: .whitespaces)
        let portText = port.trimmingCharacters(in: .whitespaces)
        if host.isEmpty {
            return user.isEmpty && portText.isEmpty ? .none : .problem("Enter the jump host's hostname, or clear its fields.")
        }
        if host.contains(where: \.isWhitespace) { return .problem("The jump host's hostname cannot have spaces.") }
        if host.contains("@") { return .problem("Put the jump host's username in its own field.") }
        if user.isEmpty { return .problem("Enter the username for the jump host.") }
        if user.contains(where: \.isWhitespace) { return .problem("The jump host's username cannot have spaces.") }
        var number = 22
        if !portText.isEmpty {
            guard let typed = Int(portText), (1...65535).contains(typed) else {
                return .problem("The jump host's port is a number from 1 to 65535.")
            }
            number = typed
        }
        return .jump(JumpHost(hostname: host, port: number, username: user))
    }

    var problem: String? {
        if case .problem(let text) = result { return text }
        return nil
    }

    /// The jump host to save, or nil for none or a field that is not valid.
    var jump: JumpHost? {
        if case .jump(let jump) = result { return jump }
        return nil
    }
}
