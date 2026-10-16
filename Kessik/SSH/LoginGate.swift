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
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                throw LoginGate.Failure.canceled
            case .passcodeNotSet:
                throw LoginGate.Failure.noPasscode
            default:
                throw LoginGate.Failure.failed
            }
        }
    }
}

/// The key and password one login offers.
struct LoginSecrets {
    var key: Curve25519.Signing.PrivateKey?
    var password: String?
}

/// Reads the key and saved password for a login, after Face ID when Settings asks for it.
/// The Keychain items stay as they are; the check sits in front of the read.
struct LoginGate {
    enum Failure: LocalizedError, Equatable {
        case canceled
        case failed
        case noPasscode

        var errorDescription: String? {
            switch self {
            case .canceled:
                return "Login canceled. Face ID or the passcode unlocks the key and saved password."
            case .failed:
                return "Face ID did not unlock the key and saved password. Try again."
            case .noPasscode:
                return "Set a passcode on this iPhone, or turn off Require Face ID in Settings."
            }
        }
    }

    var isRequired: () -> Bool
    var authenticator: Authenticator
    var readKey: () -> Curve25519.Signing.PrivateKey?
    var readSavedPassword: (Host) -> String?

    static let live = LoginGate(
        isRequired: { UserDefaults.standard.bool(forKey: SettingsKey.requireFaceID) },
        authenticator: DeviceOwnerAuthenticator(),
        readKey: DeviceKey.load,
        readSavedPassword: SavedPassword.get(for:)
    )

    /// One check per connection attempt. `typed` is a password typed for this login; without one,
    /// the saved password is used. Nothing is read from the Keychain when the check fails.
    func secrets(for host: Host, typed: String?) async throws -> LoginSecrets {
        if isRequired() {
            try await authenticator.authenticate(reason: "Log in to \(host.hostname)")
        }
        return LoginSecrets(key: readKey(), password: typed ?? readSavedPassword(host))
    }
}
