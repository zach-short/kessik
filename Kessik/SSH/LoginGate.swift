import Foundation
import CryptoKit
import LocalAuthentication

extension SettingsKey {
    /// When true, Face ID or the passcode unlocks the key and saved password for each login. Off by default.
    static let requireFaceID = "requireFaceID"
}

/// Asks the person holding the phone to prove they own it. Tests inject their own.
protocol Authenticator {
    /// Returns when the check passes. Throws `LoginGate.Failure` when it is canceled or fails.
    func authenticate(reason: String) async throws
}

/// Face ID, or Touch ID, with the device passcode as the fallback.
struct DeviceOwnerAuthenticator: Authenticator {
    func authenticate(reason: String) async throws {
        let context = LAContext()
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
                throw LoginGate.Failure.failed
            }
        } catch {
            throw LoginGate.Failure(error)
        }
    }
}

/// The key and password one login offers.
struct LoginSecrets {
    var key: DeviceKey.Key?
    var password: String?
    /// The saved password for the Mac's jump host, if it has one.
    var jumpPassword: String?
    /// The Secure Enclave key, already unlocked by Face ID for this login. See `EnclaveKey`.
    var enclaveKey: SecureEnclave.P256.Signing.PrivateKey? = nil
}

/// Reads the key and saved password for a login, after Face ID when Settings asks for it.
/// The Keychain items stay as they are; the check sits in front of the read.
struct LoginGate {
    enum Failure: LocalizedError, Equatable {
        case canceled
        case failed
        case noPasscode
        /// Face ID changed after the Secure Enclave key was made, which locks that key for good.
        case enclaveKeyLocked

        /// Maps a LocalAuthentication error. A `Failure` passes through.
        init(_ error: Error) {
            if let failure = error as? Failure {
                self = failure
                return
            }
            switch (error as? LAError)?.code {
            case .userCancel?, .appCancel?, .systemCancel?: self = .canceled
            case .passcodeNotSet?: self = .noPasscode
            default: self = .failed
            }
        }

        var errorDescription: String? {
            switch self {
            case .canceled:
                return "Login canceled. Face ID or the passcode unlocks the key and saved password."
            case .failed:
                return "Face ID did not unlock the key and saved password. Try again."
            case .noPasscode:
                return "Set a passcode on this iPhone, or turn off Require Face ID in Settings."
            case .enclaveKeyLocked:
                return "Face ID changed after the Secure Enclave key was made, so the key no longer works. Make a new key in Settings > SSH key and add it to the Mac again."
            }
        }
    }

    var isRequired: () -> Bool
    var authenticator: Authenticator
    var readKey: () -> DeviceKey.Key?
    var readSavedPassword: (Host) -> String?
    /// True when logins use the Secure Enclave key. Its own Face ID check then stands in for the gate.
    var usesEnclaveKey: () -> Bool = { false }
    /// The Secure Enclave key after its own Face ID check, or nil when it is not in use. Throws a
    /// `Failure` when Face ID is canceled or fails, or the key is locked.
    var unlockEnclaveKey: (Host) async throws -> SecureEnclave.P256.Signing.PrivateKey? = { _ in nil }

    static let live = LoginGate(
        isRequired: { UserDefaults.standard.bool(forKey: SettingsKey.requireFaceID) },
        authenticator: DeviceOwnerAuthenticator(),
        readKey: { LoginKeyKind.current == .ed25519 ? DeviceKey.load() : nil },
        readSavedPassword: SavedPassword.get(for:),
        usesEnclaveKey: { LoginKeyKind.current == .secureEnclave && EnclaveKey.exists },
        unlockEnclaveKey: EnclaveKey.unlock(for:)
    )

    /// One check per connection attempt. `typed` is a password typed for this login; without one,
    /// the saved password is used. Nothing is read from the Keychain when the check fails.
    func secrets(for host: Host, typed: String?) async throws -> LoginSecrets {
        // The Secure Enclave key asks for Face ID itself, which is a stricter check than the gate's,
        // so a login with that key shows one prompt and not two.
        let enclaveIsGate = isRequired() && usesEnclaveKey()
        if isRequired() && !enclaveIsGate {
            try await authenticator.authenticate(reason: "Log in to \(host.hostname)")
        }
        let enclaveKey: SecureEnclave.P256.Signing.PrivateKey?
        do {
            enclaveKey = try await unlockEnclaveKey(host)
        } catch {
            // As the gate, a failed check reads nothing. Otherwise the saved passwords still log in,
            // but only when every hop has one: a hop without one would fail with a misleading reason.
            if enclaveIsGate { throw error }
            let secrets = passwords(for: host, typed: typed)
            guard secrets.password != nil, host.jump == nil || secrets.jumpPassword != nil else { throw error }
            return secrets
        }
        if enclaveIsGate && enclaveKey == nil { throw Failure.failed }
        var secrets = passwords(for: host, typed: typed)
        secrets.key = readKey()
        secrets.enclaveKey = enclaveKey
        return secrets
    }

    private func passwords(for host: Host, typed: String?) -> LoginSecrets {
        LoginSecrets(key: nil, password: typed ?? readSavedPassword(host),
                     jumpPassword: host.jump.flatMap { readSavedPassword($0.login) })
    }
}
