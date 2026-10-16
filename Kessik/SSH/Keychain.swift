import Foundation
import Security
import CryptoKit
import NIOSSH

/// Generic-password items in the iOS Keychain, one service per kind of secret.
/// Items stay on this phone: no iCloud sync, and a backup does not restore them to another device.
struct Keychain {
    struct Failure: LocalizedError {
        var status: OSStatus
        var errorDescription: String? {
            let text = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "Keychain error: \(text)"
        }
    }

    let service: String

    func data(for account: String) -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func set(_ data: Data, for account: String) throws {
        let status = SecItemUpdate(base(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else {
            guard status == errSecSuccess else { throw Failure(status: status) }
            return
        }
        var item = base(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure(status: added) }
    }

    func delete(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }

    func deleteAll() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }

    var count: Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return 0 }
        return (result as? [[String: Any]])?.count ?? 0
    }

    private func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Passwords saved after a login that worked, one per `user@host:port`.
enum SavedPassword {
    private static let keychain = Keychain(service: "SSHTerm.password")

    static func get(for host: Host) -> String? {
        keychain.data(for: account(host)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func save(_ password: String, for host: Host) {
        try? keychain.set(Data(password.utf8), for: account(host))
    }

    static func remove(for host: Host) {
        keychain.delete(account(host))
    }

    static func removeAll() {
        keychain.deleteAll()
    }

    static var count: Int { keychain.count }

    private static func account(_ host: Host) -> String {
        "\(host.username)@\(host.hostname):\(host.port)"
    }
}

/// This phone's ed25519 login key. The private half stays in the Keychain;
/// the public half goes into `~/.ssh/authorized_keys` on the Mac.
enum DeviceKey {
    private static let keychain = Keychain(service: "SSHTerm.key")
    private static let account = "ed25519"
    static let comment = "sshterm@iphone"

    static func load() -> Curve25519.Signing.PrivateKey? {
        keychain.data(for: account).flatMap { try? Curve25519.Signing.PrivateKey(rawRepresentation: $0) }
    }

    @discardableResult
    static func generate() throws -> Curve25519.Signing.PrivateKey {
        let key = Curve25519.Signing.PrivateKey()
        try keychain.set(key.rawRepresentation, for: account)
        return key
    }

    static func delete() {
        keychain.delete(account)
    }

    /// Adds `line` to `~/.ssh/authorized_keys` on the Mac unless it is there already.
    /// A file without a final newline gets one first, so the key does not join the last line.
    static func installCommand(for line: String) -> String {
        let file = "$HOME/.ssh/authorized_keys"
        return "umask 077; mkdir -p \"$HOME/.ssh\" && touch \"\(file)\" && "
            + "{ [ ! -s \"\(file)\" ] || [ -z \"$(tail -c 1 \"\(file)\")\" ] || echo >> \"\(file)\"; } && "
            + "{ grep -qxF \(Tmux.quote(line)) \"\(file)\" || echo \(Tmux.quote(line)) >> \"\(file)\"; }"
    }

    /// One `authorized_keys` line: `ssh-ed25519 AAAA… sshterm@iphone`.
    static func publicLine(for key: Curve25519.Signing.PrivateKey) -> String {
        String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: key).publicKey) + " " + comment
    }
}

enum Credentials {
    /// True when a connection can start without typing a password.
    static func available(for host: Host) -> Bool {
        DeviceKey.load() != nil || SavedPassword.get(for: host) != nil
    }
}
