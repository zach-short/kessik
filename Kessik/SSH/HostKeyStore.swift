import Foundation
import NIOCore
import NIOSSH

/// Trust on first use. The first key a host presents is saved; a different key later is refused.
/// A changed key can mean the Mac was reinstalled, or that someone is in the middle of the connection.
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate {
    struct Mismatch: LocalizedError {
        var host: String
        var errorDescription: String? {
            "The host key for \(host) changed since the last connection. The connection was stopped."
        }
    }

    private let storageKey: String
    private let hostLabel: String
    private let defaults: UserDefaults

    init(host: String, port: Int, defaults: UserDefaults = .standard) {
        self.storageKey = Self.storageKey(host: host, port: port)
        self.hostLabel = host
        self.defaults = defaults
    }

    private static func storageKey(host: String, port: Int) -> String {
        "hostKey.\(host):\(port)"
    }

    /// Trusts the key saved for `old` at `new` too, for the same Mac at another address. A different
    /// key at the new address then stops the connection, as it would at the old one.
    static func copyTrust(from old: Host, to new: Host, defaults: UserDefaults = .standard) {
        guard let key = defaults.string(forKey: storageKey(host: old.hostname, port: old.port)) else { return }
        defaults.set(key, forKey: storageKey(host: new.hostname, port: new.port))
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = String(openSSHPublicKey: hostKey)
        switch defaults.string(forKey: storageKey) {
        case nil:
            defaults.set(presented, forKey: storageKey)
            validationCompletePromise.succeed(())
        case presented:
            validationCompletePromise.succeed(())
        default:
            validationCompletePromise.fail(Mismatch(host: hostLabel))
        }
    }
}
