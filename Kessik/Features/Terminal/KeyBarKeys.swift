import Foundation

/// A key the user can put in the editable part of the key bar. Each one sends a fixed byte
/// sequence, except Home and End, which follow the shell's cursor-key mode like the arrows.
struct ExtraKey: Hashable, Identifiable {
    /// Saved in UserDefaults. A symbol's id is the symbol itself.
    let id: String
    /// Shown on the button.
    let title: String
    /// Read by VoiceOver and shown in Settings.
    let label: String
    let normal: [UInt8]
    let app: [UInt8]

    func bytes(applicationCursor: Bool) -> [UInt8] {
        applicationCursor ? app : normal
    }

    private static func symbol(_ text: String, _ label: String) -> ExtraKey {
        ExtraKey(id: text, title: text, label: label, normal: Array(text.utf8), app: Array(text.utf8))
    }

    private static func named(_ id: String, _ title: String, _ label: String,
                              _ normal: [UInt8], app: [UInt8]? = nil) -> ExtraKey {
        ExtraKey(id: id, title: title, label: label, normal: normal, app: app ?? normal)
    }

    static let symbols: [ExtraKey] = [
        symbol("|", "Pipe"), symbol("~", "Tilde"), symbol("/", "Slash"), symbol("-", "Hyphen"),
        symbol("`", "Backtick"), symbol("$", "Dollar"), symbol("&", "Ampersand"), symbol("*", "Asterisk"),
        symbol("\\", "Backslash"), symbol("_", "Underscore"), symbol(":", "Colon"), symbol(";", "Semicolon"),
        symbol("\"", "Double quote"), symbol("'", "Single quote"), symbol("<", "Less than"),
        symbol(">", "Greater than"), symbol("{", "Left brace"), symbol("}", "Right brace"),
        symbol("[", "Left bracket"), symbol("]", "Right bracket"), symbol("(", "Left parenthesis"),
        symbol(")", "Right parenthesis"), symbol("=", "Equals"), symbol("+", "Plus"), symbol("#", "Hash"),
        symbol("%", "Percent"), symbol("@", "At"), symbol("!", "Exclamation mark"),
        symbol("?", "Question mark"), symbol("^", "Caret"),
    ]

    /// The same sequences SwiftTerm sends for these keys on a hardware keyboard.
    static let namedKeys: [ExtraKey] = [
        named("home", "home", "Home", [0x1b, 0x5b, 0x48], app: [0x1b, 0x4f, 0x48]),
        named("end", "end", "End", [0x1b, 0x5b, 0x46], app: [0x1b, 0x4f, 0x46]),
        named("pageUp", "pgup", "Page Up", [0x1b, 0x5b, 0x35, 0x7e]),
        named("pageDown", "pgdn", "Page Down", [0x1b, 0x5b, 0x36, 0x7e]),
        named("delete", "del", "Delete", [0x1b, 0x5b, 0x33, 0x7e]),
    ]

    static let all = symbols + namedKeys

    static func with(id: String) -> ExtraKey? {
        all.first { $0.id == id }
    }
}

/// The ordered list of extra keys on the bar: defaults, load, save and validation.
enum KeyBarKeys {
    static let defaultsKey = "keyBarKeys"
    /// More keys than this make the bar a long scroll.
    static let maxCount = 16
    /// The nine symbols the bar had before it was editable, in the same order.
    static let defaultIDs = ["|", "~", "/", "-", "`", "$", "&", "*", "\\"]
    static var defaults: [ExtraKey] { defaultIDs.compactMap(ExtraKey.with(id:)) }

    /// Unknown ids and repeats are dropped and the list is capped. An empty result is nil.
    static func validated(_ ids: [String]) -> [ExtraKey]? {
        var seen = Set<String>()
        let keys = ids
            .filter { seen.insert($0).inserted }
            .compactMap(ExtraKey.with(id:))
            .prefix(maxCount)
        return keys.isEmpty ? nil : Array(keys)
    }

    /// The saved list, or the defaults when nothing usable is saved.
    static func load(from store: UserDefaults = .standard) -> [ExtraKey] {
        guard let ids = store.object(forKey: defaultsKey) as? [String] else { return defaults }
        return validated(ids) ?? defaults
    }

    /// An empty list is not saved, so the bar never loses its keys by mistake.
    static func save(_ keys: [ExtraKey], to store: UserDefaults = .standard) {
        guard let valid = validated(keys.map(\.id)) else { return }
        store.set(valid.map(\.id), forKey: defaultsKey)
        NotificationCenter.default.post(name: .keyBarKeysChanged, object: nil)
    }

    static func reset(in store: UserDefaults = .standard) {
        store.removeObject(forKey: defaultsKey)
        NotificationCenter.default.post(name: .keyBarKeysChanged, object: nil)
    }
}

extension Notification.Name {
    /// Posted after the key list changes, so a key bar that is already open rebuilds its keys.
    static let keyBarKeysChanged = Notification.Name("keyBarKeysChanged")
}
