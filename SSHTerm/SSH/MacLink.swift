import Foundation
import Observation
import Citadel

extension SSHClient {
    /// Password login with the app's host key check and timeout.
    static func connect(to host: Host, password: String) async throws -> SSHClient {
        try await SSHClient.connect(
            host: host.hostname,
            port: host.port,
            authenticationMethod: .passwordBased(username: host.username, password: password),
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

    private(set) var state: State = .needsPassword
    /// Changed from the connect card until the settings screen lands (build step 7).
    var host: Host

    @ObservationIgnored private(set) var client: SSHClient?
    @ObservationIgnored private var generation = 0

    init(host: Host) {
        self.host = host
    }

    func connect(password: String) {
        guard state != .connecting, state != .connected else { return }
        state = .connecting
        generation += 1
        let gen = generation
        let host = host

        Task { [weak self] in
            do {
                let client = try await SSHClient.connect(to: host, password: password)
                self?.didConnect(client, gen: gen)
            } catch {
                self?.didFail(error, gen: gen)
            }
        }
    }

    /// Runs one command and returns its stdout. A non-zero exit throws.
    func run(_ command: String) async throws -> String {
        guard let client else { throw NotConnected() }
        do {
            let output = try await client.executeCommand(command)
            return String(buffer: output)
        } catch {
            if !client.isConnected { dropped(gen: generation) }
            throw error
        }
    }

    func disconnect() {
        generation += 1
        let client = client
        self.client = nil
        state = .needsPassword
        Task { try? await client?.close() }
    }

    private func didConnect(_ client: SSHClient, gen: Int) {
        guard gen == generation else {
            Task { try? await client.close() }
            return
        }
        self.client = client
        state = .connected
        client.onDisconnect { [weak self] in
            Task { @MainActor in self?.dropped(gen: gen) }
        }
    }

    private func didFail(_ error: Error, gen: Int) {
        guard gen == generation else { return }
        state = .failed(SSHSession.message(for: error, host: host))
    }

    private func dropped(gen: Int) {
        guard gen == generation, state == .connected else { return }
        client = nil
        state = .failed("The connection to \(host.hostname) dropped.")
    }
}
