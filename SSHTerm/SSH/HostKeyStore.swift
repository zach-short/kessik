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
        self.storageKey = "hostKey.\(host):\(port)"
        self.hostLabel = host
        self.defaults = defaults
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
