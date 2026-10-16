import Foundation

/// A login pasted as one line, like `ssh -p 2222 zach@mac.local` or `ssh://zach@mac.local:2222`.
/// The Mac form reads it from the hostname field and fills its other fields. This is not an
/// ssh_config parser: it knows the target, `-p`, `-l` and `-J`, and skips the other options.
struct SSHLine: Equatable {
    /// Nil when the line has no user, so the form keeps the username as typed.
    var username: String?
    var hostname: String
    var port = 22
    /// Set only for `-J`. Its username is empty when the line gives none.
    var jump: JumpHost?

    /// Options of `ssh` that take an argument.
    private static let takesArgument = Set("BbcDEeFIiJLlmOoPpQRSWw")

    /// The login in `text`, or nil when `text` is a plain hostname or is not a valid login.
    /// More than one jump host (`-J a,b`) is nil, so no hop is silently lost.
    static func parse(_ text: String) -> SSHLine? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ssh://") { return target(line) }
        let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.first == "ssh" else { return line.contains("@") ? target(line) : nil }

        var options: [Character: String] = [:]
        var index = 1
        while index < words.count, words[index].hasPrefix("-") {
            let word = words[index]
            index += 1
            if word == "--" { break }
            var flags = word.dropFirst()
            while let flag = flags.popFirst() {
                guard takesArgument.contains(flag) else { continue }
                if flags.isEmpty {
                    guard index < words.count else { return nil }
                    options[flag] = words[index]
                    index += 1
                } else {
                    options[flag] = String(flags)
                }
                break
            }
        }
        guard index < words.count, var login = target(words[index]) else { return nil }
        if let user = options["l"] { login.username = user }
        if let port = options["p"] {
            guard let number = portNumber(port) else { return nil }
            login.port = number
        }
        if let jump = options["J"] {
            guard !jump.contains(","), let hop = target(jump) else { return nil }
            login.jump = JumpHost(hostname: hop.hostname, port: hop.port, username: hop.username ?? "")
        }
        return login
    }

    /// `[user@]host[:port]`, `[user@][v6]:port` or the same as an `ssh://` URL.
    private static func target(_ text: String) -> SSHLine? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        var rest = Substring(text)
        if rest.hasPrefix("ssh://") {
            rest = rest.dropFirst(6)
            if rest.hasSuffix("/") { rest = rest.dropLast() }
        }
        var username: String?
        if let at = rest.lastIndex(of: "@") {
            username = String(rest[..<at])
            rest = rest[rest.index(after: at)...]
            if username?.isEmpty == true { return nil }
        }
        var hostname = rest
        var port = 22
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            hostname = rest[rest.index(after: rest.startIndex)..<close]
            let after = rest[rest.index(after: close)...]
            if !after.isEmpty {
                guard after.hasPrefix(":"), let number = portNumber(after.dropFirst()) else { return nil }
                port = number
            }
        } else if let colon = rest.firstIndex(of: ":"), rest.lastIndex(of: ":") == colon {
            hostname = rest[..<colon]
            guard let number = portNumber(rest[rest.index(after: colon)...]) else { return nil }
            port = number
        }
        guard !hostname.isEmpty, !hostname.contains("/") else { return nil }
        return SSHLine(username: username, hostname: String(hostname), port: port)
    }

    private static func portNumber(_ text: some StringProtocol) -> Int? {
        Int(text).flatMap { (1...65535).contains($0) ? $0 : nil }
    }
}
