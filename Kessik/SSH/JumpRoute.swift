import Foundation
import CryptoKit
import Citadel
import NIOCore
import NIOSSH

/// One login on the way to a Mac: where to connect, who logs in, and the host key check for that host.
struct LoginHop {
    enum Role: Equatable {
        case jumpHost
        case mac
    }

    var role: Role
    var target: Host
    /// Trust on first use, keyed by `target`'s own hostname and port.
    let validator: TOFUHostKeyValidator

    /// The key first, then `password`, with this hop's own host key check.
    func settings(key: DeviceKey.Key?, password: String?,
                  enclaveKey: SecureEnclave.P256.Signing.PrivateKey? = nil) -> SSHClientSettings {
        let username = target.username
        var settings = SSHClientSettings(
            host: target.hostname,
            port: target.port,
            authenticationMethod: { .custom(LoginMethods(username: username, key: key, password: password, enclaveKey: enclaveKey)) },
            hostKeyValidator: .custom(validator)
        )
        settings.connectTimeout = .seconds(10)
        return settings
    }
}

/// How the app reaches a Mac: straight to it, or through its jump host first.
enum LoginRoute {
    /// The jump host first when the Mac has one, then the Mac. Each hop checks its own host key.
    static func hops(to host: Host, defaults: UserDefaults = .standard) -> [LoginHop] {
        var hops: [LoginHop] = []
        if let jump = host.jump?.login {
            hops.append(LoginHop(role: .jumpHost, target: jump,
                                 validator: TOFUHostKeyValidator(host: jump.hostname, port: jump.port, defaults: defaults)))
        }
        hops.append(LoginHop(role: .mac, target: host,
                             validator: TOFUHostKeyValidator(host: host.hostname, port: host.port,
                                                             via: host.jump?.login, defaults: defaults)))
        return hops
    }

    /// Logs in to each hop in turn. A failure says which hop it came from. The jump host
    /// connection closes when the Mac connection closes.
    static func connect(to host: Host, secrets: LoginSecrets) async throws -> SSHClient {
        let hops = hops(to: host)
        let mac = hops[hops.count - 1]
        guard hops.count == 2, let jumpName = host.jump?.hostname else {
            return try await SSHClient.connect(to: mac.settings(key: secrets.key, password: secrets.password, enclaveKey: secrets.enclaveKey))
        }
        let jumpHop = hops[0]

        let jump: SSHClient
        do {
            jump = try await SSHClient.connect(to: jumpHop.settings(key: secrets.key, password: secrets.jumpPassword, enclaveKey: secrets.enclaveKey))
        } catch {
            throw HopFailure.wrap(error, role: .jumpHost, target: jumpHop.target, jumpName: jumpName)
        }
        do {
            let settings = mac.settings(key: secrets.key, password: secrets.password, enclaveKey: secrets.enclaveKey)
            let client = try await withTimeout(15) { try await jump.jump(to: settings) }
            JumpConnections.attach(jump, to: client)
            return client
        } catch {
            try? await jump.close()
            throw HopFailure.wrap(error, role: .mac, target: mac.target, jumpName: jumpName)
        }
    }
}

/// A login through a jump host that failed, and on which hop. `SSHSession.message` turns it into text.
struct HopFailure: Error {
    var role: LoginHop.Role
    var target: Host
    var jumpName: String
    var underlying: Error

    /// A cancel stays a cancel, so the callers that ignore it still do.
    static func wrap(_ error: Error, role: LoginHop.Role, target: Host, jumpName: String) -> Error {
        if error is CancellationError { return error }
        return HopFailure(role: role, target: target, jumpName: jumpName, underlying: error)
    }

    /// `describe` is the plain message for one error at one host.
    func text(_ describe: (Error, Host) -> String) -> String {
        switch role {
        case .jumpHost:
            if let error = underlying as? SSHClientError, case .allAuthenticationOptionsFailed = error {
                return "Jump host: \(jumpName) refused the login. Check the jump host username. Save its password in the Mac's settings, or add this phone's key to the jump host."
            }
            return "Jump host: " + describe(underlying, target)
        case .mac:
            if let error = underlying as? NIOSSHError, error.type == .channelSetupRejected {
                return "Mac, through \(jumpName): the jump host could not open a connection to \(target.hostname). Check the Mac's hostname as the jump host sees it, and check that the jump host allows TCP forwarding."
            }
            return "Mac, through \(jumpName): " + describe(underlying, target)
        }
    }
}

/// Citadel keeps one disconnect handler per client, and MacLink sets its own. The jump host
/// connection under a Mac connection is kept here, so either handler closes it.
enum JumpConnections {
    private struct Entry {
        weak var mac: SSHClient?
        let jump: SSHClient
    }

    private static let lock = NSLock()
    private static var entries: [ObjectIdentifier: Entry] = [:]

    static func attach(_ jump: SSHClient, to mac: SSHClient) {
        lock.lock()
        // A Mac client freed without a close never calls its handler. Its jump host connection closes here.
        let orphans = entries.filter { $0.value.mac == nil }
        for id in orphans.keys { entries[id] = nil }
        entries[ObjectIdentifier(mac)] = Entry(mac: mac, jump: jump)
        lock.unlock()
        for orphan in orphans.values { Task { try? await orphan.jump.close() } }
        mac.whenDisconnected {}
    }

    /// Closes the jump host connection under `mac`, if it has one.
    static func close(under mac: SSHClient) {
        lock.lock()
        let id = ObjectIdentifier(mac)
        let entry = entries[id]
        if entry?.mac === mac { entries[id] = nil }
        lock.unlock()
        guard let entry, entry.mac === mac else { return }
        Task { try? await entry.jump.close() }
    }
}

extension SSHClient {
    /// Use in place of `onDisconnect`. It also closes the jump host connection under this one.
    func whenDisconnected(_ perform: @escaping @Sendable () -> Void) {
        onDisconnect { [weak self] in
            if let self { JumpConnections.close(under: self) }
            perform()
        }
    }
}
