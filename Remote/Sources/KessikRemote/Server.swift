import Foundation
import Network
import RemoteWire

/// Listens on the loopback address and turns each line from a phone into input. Everything runs
/// on the main queue: the lines are small and the input calls are quick.
final class Server {
    private let token: String
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    /// Why the server is not listening, for the menu.
    private(set) var problem: String?
    var isTrusted: () -> Bool = { false }

    var phones: Int { clients.values.filter(\.authed).count }

    init(token: String) {
        self.token = token
    }

    func start() {
        let tcp = NWProtocolTCP.Options()
        // A pointer move must go out at once, not wait for more bytes.
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.allowLocalEndpointReuse = true
        // Loopback only. Nothing on the network can reach this port; the phone comes in over SSH.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                     port: NWEndpoint.Port(rawValue: UInt16(RemoteWire.port))!)
        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed(let error), .waiting(let error):
                    self?.problem = "Port \(RemoteWire.port) is not free: \(error.localizedDescription)"
                case .ready:
                    self?.problem = nil
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            problem = "Could not listen on port \(RemoteWire.port): \(error.localizedDescription)"
        }
    }

    func trustChanged(_ trusted: Bool) {
        for client in clients.values where client.authed {
            client.send(.trusted(trusted))
        }
    }

    private func accept(_ connection: NWConnection) {
        let client = Client(connection: connection)
        let id = ObjectIdentifier(client)
        clients[id] = client
        client.onLine = { [weak self, weak client] line in
            guard let self, let client else { return }
            self.handle(line, from: client)
        }
        client.onClose = { [weak self] in
            self?.clients[id] = nil
            // A phone that drops with a button held must not leave the Mac in a drag.
            if self?.phones == 0 { Input.releaseButtons() }
        }
        client.start()
        // A connection that does not send the token has five seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak client] in
            if let client, !client.authed { client.close() }
        }
    }

    private func handle(_ line: String, from client: Client) {
        guard let command = RemoteCommand(line: line) else { return }
        if !client.authed {
            if case .auth(let sent) = command, sent == token {
                client.authed = true
                client.send(.hello(version: RemoteWire.version, trusted: isTrusted()))
            } else {
                client.send(.denied) { [weak client] in client?.close() }
            }
            return
        }
        Input.perform(command)
    }
}

/// One connection from a phone.
private final class Client {
    private let connection: NWConnection
    private var buffer = RemoteLineBuffer()
    private var closed = false
    var authed = false
    var onLine: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.finish()
            default: break
            }
        }
        connection.start(queue: .main)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, done, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                guard let lines = self.buffer.append(data) else { return self.close() }
                for line in lines where !self.closed { self.onLine(line) }
            }
            if done || error != nil { return self.close() }
            self.receive()
        }
    }

    /// `then` runs after the bytes are out, so a close does not cut the reply off.
    func send(_ reply: RemoteReply, then: @escaping () -> Void = {}) {
        guard !closed else { return }
        connection.send(content: Data((reply.line + "\n").utf8), completion: .contentProcessed { _ in then() })
    }

    func close() {
        guard !closed else { return }
        connection.cancel()
        finish()
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        onClose()
    }
}
