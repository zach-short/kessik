import Foundation
import Security
import CryptoKit
import LocalAuthentication
import NIOSSH

extension SettingsKey {
    /// Which login key the app holds and offers. See `LoginKeyKind`. Holds no secret.
    static let loginKeyKind = "loginKeyKind"
}

/// The two kinds of login key. The person picks one in Settings > SSH key, and logins offer only that one.
enum LoginKeyKind: String, CaseIterable, Identifiable {
    /// The ed25519 key in `DeviceKey`.
    case ed25519
    /// The P-256 key in `EnclaveKey`. Every login asks for Face ID.
    case secureEnclave

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ed25519: return "Ed25519"
        case .secureEnclave: return "Secure Enclave"
        }
    }

    /// The saved choice. A phone without a Secure Enclave, such as the simulator, always uses ed25519.
    static var current: LoginKeyKind {
        let saved = UserDefaults.standard.string(forKey: SettingsKey.loginKeyKind).flatMap(LoginKeyKind.init(rawValue:))
        return resolve(saved, enclaveAvailable: SecureEnclave.isAvailable)
    }

    static func resolve(_ saved: LoginKeyKind?, enclaveAvailable: Bool) -> LoginKeyKind {
        guard let saved, saved != .secureEnclave || enclaveAvailable else { return .ed25519 }
        return saved
    }
}

/// The key of the picked kind, for Settings and for the "key is tried first" notes.
enum PhoneKey {
    /// The `authorized_keys` line of the picked key, or nil when that kind has no key yet.
    static func publicLine(_ kind: LoginKeyKind = .current) -> String? {
        switch kind {
        case .ed25519: return DeviceKey.load().map(DeviceKey.publicLine(for:))
        case .secureEnclave: return EnclaveKey.load().map(EnclaveKey.publicLine(for:))
        }
    }

    static var exists: Bool {
        switch LoginKeyKind.current {
        case .ed25519: return DeviceKey.load() != nil
        case .secureEnclave: return EnclaveKey.exists
        }
    }

    /// Makes a new key of `kind` in place of the old one and returns its public line.
    static func generate(_ kind: LoginKeyKind) throws -> String {
        switch kind {
        case .ed25519: return DeviceKey.publicLine(for: try DeviceKey.generate())
        case .secureEnclave: return EnclaveKey.publicLine(for: try EnclaveKey.generate())
        }
    }

    static func delete(_ kind: LoginKeyKind) {
        switch kind {
        case .ed25519: DeviceKey.delete()
        case .secureEnclave: EnclaveKey.delete()
        }
    }
}

/// A P-256 login key made in the Secure Enclave. The private key never leaves the Enclave, and
/// each signature needs Face ID from the faces enrolled when the key was made. The Keychain holds
/// only the key's `dataRepresentation`, a handle that works on this phone's Enclave and nowhere else.
enum EnclaveKey {
    struct Failure: LocalizedError {
        var errorDescription: String?
    }

    private static let keychain = Keychain(service: "SSHTerm.key")
    private static let account = "secureEnclaveP256"
    static let comment = "kessik"
    static let aboutText = "A Secure Enclave key never leaves this iPhone, and each login asks for Face ID before the key signs. "
        + "A reset of Face ID, or a new appearance added to it, stops the key working. macOS accepts this key type."

    static var isAvailable: Bool { SecureEnclave.isAvailable }

    static var exists: Bool { keychain.data(for: account) != nil }

    /// The key without Face ID. It can give its public key but asks for Face ID to sign.
    static func load() -> SecureEnclave.P256.Signing.PrivateKey? {
        guard isAvailable, let data = keychain.data(for: account) else { return nil }
        return try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
    }

    @discardableResult
    static func generate() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard isAvailable else {
            throw Failure(errorDescription: "This iPhone has no Secure Enclave. Use the ed25519 key.")
        }
        var error: NSError?
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw Failure(errorDescription: "Set up Face ID on this iPhone first. The Secure Enclave key needs it for each login.")
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: try accessControl())
        keychain.delete(account)
        try keychain.set(key.dataRepresentation, for: account, accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        return key
    }

    static func delete() {
        keychain.delete(account)
    }

    /// One `authorized_keys` line: `ecdsa-sha2-nistp256 AAAA… kessik`.
    static func publicLine(for key: SecureEnclave.P256.Signing.PrivateKey) -> String {
        publicLine(for: NIOSSHPrivateKey(secureEnclaveP256Key: key))
    }

    static func publicLine(for key: NIOSSHPrivateKey) -> String {
        String(openSSHPublicKey: key.publicKey) + " " + comment
    }

    /// Asks for Face ID and returns the key ready to sign this login without asking again.
    /// Nil when the picked kind is ed25519 or there is no key. Throws `LoginGate.Failure` when Face ID
    /// is canceled or fails, and `.enclaveKeyLocked` when the key no longer signs.
    ///
    /// Face ID runs here and not inside the signature, because NIOSSH signs on its event loop and
    /// the Face ID sheet would block that thread while it is on screen.
    static func unlock(for host: Host) async throws -> SecureEnclave.P256.Signing.PrivateKey? {
        guard LoginKeyKind.current == .secureEnclave, isAvailable, let data = keychain.data(for: account) else { return nil }
        let context = LAContext()
        do {
            let reason = "Log in to \(host.hostname)"
            guard try await context.evaluateAccessControl(accessControl(), operation: .useKeySign, localizedReason: reason) else {
                throw LoginGate.Failure.failed
            }
        } catch {
            throw LoginGate.Failure(error)
        }
        // The check above reads a new access control, so it passes even after a reset of Face ID has
        // locked the key. One signature here finds that out before the login, off NIOSSH's event loop.
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data, authenticationContext: context)
            _ = try key.signature(for: Data("kessik".utf8))
            return key
        } catch {
            throw LoginGate.Failure.enclaveKeyLocked
        }
    }

    /// Signing needs Face ID as it is set up now. A reset or a new appearance in Face ID, or the passcode,
    /// cannot unlock the key.
    private static func accessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet], &error
        ) else {
            throw error.map { $0.takeRetainedValue() as Error } ?? Failure(errorDescription: "Could not set up the key's Face ID check.")
        }
        return access
    }
}
