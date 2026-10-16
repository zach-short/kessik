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

    /// Where the trusted key is saved. Tests read it to check which host a validator guards.
    let storageKey: String
    private let hostLabel: String
    private let defaults: UserDefaults

    /// `via` is the jump host the connection goes through. A name such as `localhost` or a LAN address
    /// means a different Mac behind each jump host, so the trusted key is saved per jump host too.
    init(host: String, port: Int, via jump: Host? = nil, defaults: UserDefaults = .standard) {
        let own = Self.storageKey(host: host, port: port)
        self.storageKey = jump.map { "hostKey.\($0.hostname):\($0.port)/" + own.dropFirst("hostKey.".count) } ?? own
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
