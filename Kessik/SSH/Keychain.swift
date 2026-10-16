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

    /// `accessible` applies when the item is new. An update keeps the item's old setting.
    func set(_ data: Data, for account: String, accessible: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) throws {
        let status = SecItemUpdate(base(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else {
            guard status == errSecSuccess else { throw Failure(status: status) }
            return
        }
        var item = base(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = accessible
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

/// This phone's login key in the Keychain: a generated ed25519 key, or an imported ed25519 or ECDSA key.
/// The private half stays in the Keychain; the public half goes into `~/.ssh/authorized_keys` on the Mac.
enum DeviceKey {
    /// A private key the Keychain can hold.
    enum Key {
        case ed25519(Curve25519.Signing.PrivateKey)
        case p256(P256.Signing.PrivateKey)
        case p384(P384.Signing.PrivateKey)
        case p521(P521.Signing.PrivateKey)

        /// An ECDSA key from its private scalar. The length picks the curve: 32, 48 or 66 bytes.
        init?(ecdsaRaw raw: Data) {
            switch raw.count {
            case 32: guard let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) else { return nil }; self = .p256(key)
            case 48: guard let key = try? P384.Signing.PrivateKey(rawRepresentation: raw) else { return nil }; self = .p384(key)
            case 66: guard let key = try? P521.Signing.PrivateKey(rawRepresentation: raw) else { return nil }; self = .p521(key)
            default: return nil
            }
        }

        var rawRepresentation: Data {
            switch self {
            case .ed25519(let key): return key.rawRepresentation
            case .p256(let key): return key.rawRepresentation
            case .p384(let key): return key.rawRepresentation
            case .p521(let key): return key.rawRepresentation
            }
        }

        var sshKey: NIOSSHPrivateKey {
            switch self {
            case .ed25519(let key): return NIOSSHPrivateKey(ed25519Key: key)
            case .p256(let key): return NIOSSHPrivateKey(p256Key: key)
            case .p384(let key): return NIOSSHPrivateKey(p384Key: key)
            case .p521(let key): return NIOSSHPrivateKey(p521Key: key)
            }
        }

        /// The key type as Settings shows it.
        var label: String {
            switch self {
            case .ed25519: return "Ed25519"
            case .p256: return "ECDSA P-256"
            case .p384: return "ECDSA P-384"
            case .p521: return "ECDSA P-521"
            }
        }
    }

    private static let keychain = Keychain(service: "SSHTerm.key")
    /// One item at a time: an ed25519 key under `account`, or an ECDSA key under `ecdsaAccount`.
    private static let account = "ed25519"
    private static let ecdsaAccount = "ecdsa"
    static let comment = "sshterm@iphone"

    static func load() -> Key? {
        if let data = keychain.data(for: account), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            return .ed25519(key)
        }
        return keychain.data(for: ecdsaAccount).flatMap(Key.init(ecdsaRaw:))
    }

    /// The type of the saved key, or "Ed25519", the type a new key gets.
    static var label: String { load()?.label ?? "Ed25519" }

    @discardableResult
    static func generate() throws -> Key {
        let key = Key.ed25519(Curve25519.Signing.PrivateKey())
        try save(key)
        return key
    }

    /// Saves `key` in place of the current one.
    static func save(_ key: Key) throws {
        if case .ed25519 = key {
            try keychain.set(key.rawRepresentation, for: account)
            keychain.delete(ecdsaAccount)
        } else {
            try keychain.set(key.rawRepresentation, for: ecdsaAccount)
            keychain.delete(account)
        }
    }

    static func delete() {
        keychain.delete(account)
        keychain.delete(ecdsaAccount)
    }

    /// Adds `line` to `~/.ssh/authorized_keys` on the Mac unless it is there already.
    /// A file without a final newline gets one first, so the key does not join the last line.
    static func installCommand(for line: String) -> String {
        let file = "$HOME/.ssh/authorized_keys"
        return "umask 077; mkdir -p \"$HOME/.ssh\" && touch \"\(file)\" && "
            + "{ [ ! -s \"\(file)\" ] || [ -z \"$(tail -c 1 \"\(file)\")\" ] || echo >> \"\(file)\"; } && "
            + "{ grep -qxF \(Tmux.quote(line)) \"\(file)\" || echo \(Tmux.quote(line)) >> \"\(file)\"; }"
    }

    /// One `authorized_keys` line: `ssh-ed25519 AAAA… sshterm@iphone`, or `ecdsa-sha2-nistp384 AAAA…` for ECDSA.
    static func publicLine(for key: Key) -> String {
        String(openSSHPublicKey: key.sshKey.publicKey) + " " + comment
    }
}

enum Credentials {
    /// True when a connection can start without typing a password. Through a jump host, both hops
    /// need the key or their own saved password.
    static func available(for host: Host) -> Bool {
        if PhoneKey.exists { return true }
        guard SavedPassword.get(for: host) != nil else { return false }
        return host.jump.map { SavedPassword.get(for: $0.login) != nil } ?? true
    }
}
