import Foundation

/// The lines the phone and Kessik Remote on the Mac send each other. One command or reply per line.
/// The iPhone app compiles this folder into its own module, and the Mac helper imports it as a
/// library, so the two sides cannot disagree about a line.
public enum RemoteWire {
    public static let version = 1
    /// Kessik Remote listens here on the Mac's loopback address only. The phone reaches it
    /// through the SSH connection.
    public static let port = 47815
    /// Where Kessik Remote keeps its token, below the home folder on the Mac. The phone reads it
    /// over SSH and sends it first, so another program on the Mac cannot use the port.
    public static let tokenPath = "Library/Application Support/KessikRemote/token"
}

public enum RemoteButton: String, Sendable, CaseIterable {
    case left, right
}

public enum RemotePress: String, Sendable, CaseIterable {
    case down, up, click
}

public enum RemoteKey: String, Sendable, CaseIterable {
    case up, down, left, right, enter, escape, space, delete, tab
}

public enum RemoteAction: String, Sendable, CaseIterable {
    case back, home, search, power, volumeUp, volumeDown, mute, playPause, next, previous
}

/// What the phone sends.
public enum RemoteCommand: Equatable, Sendable {
    case auth(String)
    /// Pointer movement in points.
    case move(dx: Double, dy: Double)
    case button(RemoteButton, RemotePress)
    /// Scroll in pixels. Positive `dy` moves the content down, as the fingers do.
    case scroll(dx: Double, dy: Double)
    case key(RemoteKey)
    case text(String)
    case action(RemoteAction)

    public var line: String {
        switch self {
        case .auth(let token): "auth \(token)"
        case .move(let dx, let dy): "m \(Self.number(dx)) \(Self.number(dy))"
        case .button(let button, let press): "b \(button.rawValue) \(press.rawValue)"
        case .scroll(let dx, let dy): "s \(Self.number(dx)) \(Self.number(dy))"
        case .key(let key): "k \(key.rawValue)"
        case .text(let text): "t \(Data(text.utf8).base64EncodedString())"
        case .action(let action): "a \(action.rawValue)"
        }
    }

    public init?(line: String) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let verb = parts.first else { return nil }
        let args = Array(parts.dropFirst())
        switch (verb, args.count) {
        case ("auth", 1):
            self = .auth(args[0])
        case ("m", 2):
            guard let dx = Self.finite(args[0]), let dy = Self.finite(args[1]) else { return nil }
            self = .move(dx: dx, dy: dy)
        case ("b", 2):
            guard let button = RemoteButton(rawValue: args[0]), let press = RemotePress(rawValue: args[1]) else { return nil }
            self = .button(button, press)
        case ("s", 2):
            guard let dx = Self.finite(args[0]), let dy = Self.finite(args[1]) else { return nil }
            self = .scroll(dx: dx, dy: dy)
        case ("k", 1):
            guard let key = RemoteKey(rawValue: args[0]) else { return nil }
            self = .key(key)
        case ("t", 1):
            guard let data = Data(base64Encoded: args[0]), let text = String(data: data, encoding: .utf8) else { return nil }
            self = .text(text)
        case ("a", 1):
            guard let action = RemoteAction(rawValue: args[0]) else { return nil }
            self = .action(action)
        default:
            return nil
        }
    }

    /// One decimal place is finer than a pointer needs and keeps the line short.
    private static func number(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func finite(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }
}

/// What Kessik Remote sends back.
public enum RemoteReply: Equatable, Sendable {
    /// The token was right. `trusted` is false until the Mac user allows Kessik Remote under
    /// Accessibility, and the Mac ignores input until then.
    case hello(version: Int, trusted: Bool)
    /// The Accessibility permission changed while connected.
    case trusted(Bool)
    /// The token was wrong. The Mac closes the connection.
    case denied

    public var line: String {
        switch self {
        case .hello(let version, let trusted): "hello \(version) \(trusted ? 1 : 0)"
        case .trusted(let trusted): "ax \(trusted ? 1 : 0)"
        case .denied: "denied"
        }
    }

    public init?(line: String) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        switch (parts.first, parts.count) {
        case ("hello", 3):
            guard let version = Int(parts[1]), let flag = Self.flag(parts[2]) else { return nil }
            self = .hello(version: version, trusted: flag)
        case ("ax", 2):
            guard let flag = Self.flag(parts[1]) else { return nil }
            self = .trusted(flag)
        case ("denied", 1):
            self = .denied
        default:
            return nil
        }
    }

    private static func flag(_ text: String) -> Bool? {
        switch text {
        case "1": true
        case "0": false
        default: nil
        }
    }
}

/// Collects bytes from a socket and gives back whole lines. Both sides read with it.
public struct RemoteLineBuffer: Sendable {
    /// A line longer than this is not one of ours, so the reader drops the connection.
    public static let limit = 64 * 1024
    private var pending = Data()

    public init() {}

    /// The complete lines in `pending` plus `bytes`, or nil when a line passes the limit.
    public mutating func append(_ bytes: Data) -> [String]? {
        pending.append(bytes)
        var lines: [String] = []
        while let end = pending.firstIndex(of: 0x0A) {
            let raw = pending[pending.startIndex..<end]
            pending = Data(pending[pending.index(after: end)...])
            if let line = String(data: raw, encoding: .utf8) {
                lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return pending.count > Self.limit ? nil : lines
    }
}
