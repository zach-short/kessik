import Foundation
import Observation
import Citadel

/// The second login to the Mac, as the assistant's own user (`agent` by default). That user's key is
/// forced to the assistant command on the Mac, so this connection can only send assistant requests,
/// never a shell. The assistant's data stays on the Mac; the admin login that the Sessions tab and
/// Claude Code use cannot read it.
@MainActor
@Observable
final class AssistantLink {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    struct Refused: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private(set) var state: State = .idle
    /// The admin user's home folder on the Mac, read over the Sessions login when the tab opens.
    /// Job folders must be inside it.
    var macHome: String?
    @ObservationIgnored private var client: SSHClient?
    @ObservationIgnored private var connecting: Task<SSHClient, Error>?
    @ObservationIgnored private var forHost: Host?

    /// The Mac from Settings with the assistant's user in place of the admin user.
    static func host(for mac: Host, user: String) -> Host {
        var host = mac
        host.username = user.trimmingCharacters(in: .whitespaces).isEmpty ? "agent" : user.trimmingCharacters(in: .whitespaces)
        host.startCommand = nil
        return host
    }

    func disconnect() {
        connecting?.cancel()
        connecting = nil
        let old = client
        client = nil
        forHost = nil
        state = .idle
        Task { try? await old?.close() }
    }

    /// Sends one request and decodes the reply. `T` is the reply's own fields; `ok` and `error` are checked here.
    func call<T: Decodable>(_ type: T.Type, to mac: Host, user: String, _ verb: String, _ numbers: [Int] = [],
                            payload: [String: Any]? = nil) async throws -> T {
        let line = try AssistantRequest.line(verb, numbers, payload: payload)
        let client = try await ensureConnected(mac: mac, user: user)
        let output: String
        do {
            output = String(buffer: try await withTimeout(20) { try await client.executeCommand(line) })
        } catch {
            if error is TimedOut || !client.isConnected { dropClient() }
            throw error
        }
        return try Self.decode(type, from: output)
    }

    /// Reads one JSON reply: `{"ok": true, ...}` or `{"ok": false, "error": "..."}`. A login shell may
    /// print lines first, so this reads the last line that starts with `{`.
    nonisolated static func decode<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        guard let line = output.split(separator: "\n").last(where: { $0.hasPrefix("{") }), let data = line.data(using: .utf8) else {
            throw Refused(message: "The Mac did not answer as the assistant. Run `make assistant-install` on the Mac.")
        }
        let envelope = try JSONDecoder().decode(AssistantEnvelope.self, from: data)
        guard envelope.ok else { throw Refused(message: envelope.error ?? "The assistant refused the request.") }
        return try Assistant.decoder().decode(type, from: data)
    }

    private func ensureConnected(mac: Host, user: String) async throws -> SSHClient {
        let host = Self.host(for: mac, user: user)
        if let forHost, !forHost.sameLogin(as: host) { disconnect() }
        if let connecting { return try await connecting.value }
        if let client, client.isConnected { return client }
        state = .connecting
        forHost = host
        let task = Task { try await SSHClient.connect(to: host, typed: nil) }
        connecting = task
        do {
            let client = try await task.value
            connecting = nil
            self.client = client
            state = .connected
            client.whenDisconnected { [weak self] in
                Task { @MainActor in self?.dropClient() }
            }
            return client
        } catch {
            connecting = nil
            state = .failed(SSHSession.message(for: error, host: host))
            throw error
        }
    }

    private func dropClient() {
        let old = client
        client = nil
        if state == .connected { state = .idle }
        Task { try? await old?.close() }
    }
}

/// The part of every reply that says whether the request worked.
struct AssistantEnvelope: Decodable {
    var ok: Bool
    var error: String?
}

/// Replies, one per verb.
enum AssistantReply {
    struct Ping: Decodable { var version: Int; var facts: Int; var repos: Int }
    struct Convs: Decodable { var convs: [Assistant.Conversation] }
    struct Conv: Decodable { var messages: [Assistant.Message]; var turn: Assistant.Turn? }
    struct Sent: Decodable { var conv: Int; var turn: Int; var message: Int; var queuedBehind: Bool }
    struct TurnOnly: Decodable { var turn: Assistant.Turn? }
    struct Facts: Decodable { var facts: [Assistant.Fact] }
    struct Added: Decodable { var id: Int }
    struct Repos: Decodable { var repos: Int }
    struct Approved: Decodable { var job: Assistant.JobSpec }
    struct Jobs: Decodable { var jobs: [Assistant.Job] }
    struct Drafts: Decodable { var drafts: [Assistant.Draft] }
    struct HealthReply: Decodable { var health: Assistant.Health }
    struct Digest: Decodable { var sent: Bool; var output: String }
    struct Empty: Decodable {}
}
