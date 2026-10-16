import Foundation
import Observation
import Citadel

extension SSHClient {
    /// Key, then password login, with the app's host key check and timeout.
    static func connect(to host: Host, password: String?) async throws -> SSHClient {
        try await SSHClient.connect(
            host: host.hostname,
            port: host.port,
            authenticationMethod: .custom(LoginMethods(username: host.username, key: DeviceKey.load(), password: password)),
            hostKeyValidator: .custom(TOFUHostKeyValidator(host: host.hostname, port: host.port)),
            reconnect: .never,
            connectTimeout: .seconds(10)
        )
    }
}

/// One SSH connection to the Mac that the Sessions tab keeps open. It runs short commands
/// (tmux ls, folder lists), and terminals opened from the tab share it, so one password covers both.
@MainActor
@Observable
final class MacLink {
    enum State: Equatable {
        case needsPassword
        case connecting
        case connected
        case failed(String)
    }

    struct NotConnected: LocalizedError {
        var errorDescription: String? { "Not connected to the Mac." }
    }

    struct NeedsLogin: LocalizedError {
        var errorDescription: String? { "Log in again in the Sessions tab, then reopen this session." }
    }

    private(set) var state: State = .needsPassword
    /// The Mac from Settings. Change it with `use(_:)`.
    private(set) var host: Host
    /// After a login to a `.local` name: the Mac's Tailscale address, which works away from that Wi-Fi.
    private(set) var tailscaleAddress: String?
    /// After a login to a `.local` name: true when the Mac has no Tailscale address.
    private(set) var tailscaleMissing = false

    @ObservationIgnored private(set) var client: SSHClient?
    @ObservationIgnored private var connecting: Task<SSHClient, Error>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var triedSaved = false
    @ObservationIgnored private var probing = false
    @ObservationIgnored private var lastAutoReconnect: Date?

    init(host: Host) {
        self.host = host
    }

    /// `password` nil means the key and the saved password only. `remember` saves a typed password
    /// once the login works, or removes a saved one.
    func connect(password: String?, remember: Bool = true) {
        guard state != .connecting, state != .connected else { return }
        Task { _ = try? await establish(password: password, remember: remember) }
    }

    /// Connects with saved credentials once per launch, so Disconnect stays disconnected.
    func connectSavedOnce() {
        guard !triedSaved, state == .needsPassword, Credentials.available(for: host) else { return }
        triedSaved = true
        connect(password: nil)
    }

    /// The open client, logging in with the key or saved password when there is none.
    /// `verify` checks first that the Mac still answers, so a reattach after sleep does not hang.
    func ensureConnected(verify: Bool = false) async throws -> SSHClient {
        if let connecting { return try await connecting.value }
        if let client, state == .connected {
            if !verify { return client }
            let gen = generation
            if await client.isAlive() { return client }
            if gen == generation { drop(gen: gen, reconnect: false) }
            if let connecting { return try await connecting.value }
        }
        guard Credentials.available(for: host) else { throw NeedsLogin() }
        return try await establish(password: nil, remember: true)
    }

    /// Runs one command and returns its stdout. A non-zero exit throws.
    func run(_ command: String) async throws -> String {
        guard let client else { throw NotConnected() }
        let gen = generation
        do {
            let output = try await withTimeout(20) { try await client.executeCommand(command) }
            return String(buffer: output)
        } catch {
            if error is TimedOut || !client.isConnected { drop(gen: gen) }
            throw error
        }
    }

    /// Checks that the Mac still answers. Called when the app comes back, when the network
    /// changes, and on a timer, because a dead socket after sleep reports no error.
    func checkAlive() {
        guard state == .connected, !probing, let client else { return }
        probing = true
        let gen = generation
        Task { [weak self] in
            let alive = await client.isAlive()
            guard let self else { return }
            probing = false
            if !alive { drop(gen: gen) }
        }
    }

    /// Switches to the Mac saved in Settings. A different login closes the open connection,
    /// and the terminals that share it, because they belong to the old Mac.
    func use(_ newHost: Host) {
        let changed = !newHost.sameLogin(as: host)
        host = newHost
        guard changed else { return }
        disconnect()
        triedSaved = false
        tailscaleAddress = nil
        tailscaleMissing = false
    }

    func disconnect() {
        generation += 1
        connecting?.cancel()
        connecting = nil
        let client = client
        self.client = nil
        state = .needsPassword
        Task { try? await client?.close() }
    }

    private func establish(password: String?, remember: Bool) async throws -> SSHClient {
        state = .connecting
        generation += 1
        let gen = generation
        let host = host
        let typed = password
        let password = password ?? SavedPassword.get(for: host)
        let task = Task { try await SSHClient.connect(to: host, password: password) }
        connecting = task

        do {
            let client = try await task.value
            if let typed {
                if remember { SavedPassword.save(typed, for: host) } else { SavedPassword.remove(for: host) }
            }
            guard gen == generation else {
                Task { try? await client.close() }
                throw CancellationError()
            }
            connecting = nil
            self.client = client
            state = .connected
            client.onDisconnect { [weak self] in
                Task { @MainActor in self?.drop(gen: gen) }
            }
            // Again on each login until found, so Tailscale installed later shows up.
            if host.isLocalName, tailscaleAddress == nil {
                Task { await lookUpTailscale(gen: gen) }
            }
            return client
        } catch {
            if gen == generation {
                connecting = nil
                state = .failed(SSHSession.message(for: error, host: host))
            }
            throw error
        }
    }

    /// A `.local` name works only on the Mac's Wi-Fi. Asks the Mac for its Tailscale address, so the
    /// Sessions tab can offer one that works on any network.
    private func lookUpTailscale(gen: Int) async {
        guard let output = try? await run(TailscaleAddress.command), gen == generation else { return }
        tailscaleAddress = TailscaleAddress.parse(output)
        tailscaleMissing = tailscaleAddress == nil
    }

    /// Closes a dead connection, which also ends the terminals that share it. With a key or saved
    /// password it logs in again once, so the session list comes back without a tap.
    private func drop(gen: Int, reconnect: Bool = true) {
        guard gen == generation, state == .connected else { return }
        let client = client
        self.client = nil
        state = .failed(SSHSession.message(for: ConnectionLost(), host: host))
        Task { try? await client?.close() }

        let recent = lastAutoReconnect.map { Date.now.timeIntervalSince($0) < 15 } ?? false
        guard reconnect, !recent, Credentials.available(for: host) else { return }
        lastAutoReconnect = .now
        Task { _ = try? await establish(password: nil, remember: true) }
    }
}
