import Foundation
import Observation
import Citadel
import NIOCore
import NIOSSH

/// One interactive shell over SSH. Bytes from the Mac go to `onOutput`;
/// keystrokes and resizes go in through `send` and `resize`, in order.
@MainActor
@Observable
final class SSHSession {
    enum State: Equatable {
        case needsPassword
        case connecting
        case connected
        case disconnected
        case failed(String)
    }

    private(set) var state: State = .needsPassword
    let host: Host

    /// Set by the terminal view. Called on the main actor.
    @ObservationIgnored var onOutput: ((ArraySlice<UInt8>) -> Void)?

    private enum Outbound {
        case data([UInt8])
        case resize(cols: Int, rows: Int)
    }

    @ObservationIgnored private var outbound: AsyncStream<Outbound>.Continuation?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var client: SSHClient?
    @ObservationIgnored private var size = (cols: 80, rows: 24)
    /// Bumped on each connect so a late callback from an old connection is ignored.
    @ObservationIgnored private var generation = 0

    init(host: Host) {
        self.host = host
    }

    func connect(password: String) {
        guard state != .connecting, state != .connected else { return }
        state = .connecting
        generation += 1
        let gen = generation

        let (stream, continuation) = AsyncStream<Outbound>.makeStream()
        outbound = continuation
        let host = host
        let size = size

        task = Task { [weak self] in
            do {
                let client = try await SSHClient.connect(
                    host: host.hostname,
                    port: host.port,
                    authenticationMethod: .passwordBased(username: host.username, password: password),
                    hostKeyValidator: .custom(TOFUHostKeyValidator(host: host.hostname, port: host.port)),
                    reconnect: .never,
                    connectTimeout: .seconds(10)
                )
                self?.didConnect(client, gen: gen)

                let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: size.cols,
                    terminalRowHeight: size.rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([:])
                )
                try await client.withPTY(request) { inbound, writer in
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await item in stream {
                                switch item {
                                case .data(let bytes):
                                    try await writer.write(ByteBuffer(bytes: bytes))
                                case .resize(let cols, let rows):
                                    try await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
                                }
                            }
                        }
                        group.addTask {
                            for try await chunk in inbound {
                                let buffer: ByteBuffer
                                switch chunk {
                                case .stdout(let b), .stderr(let b): buffer = b
                                }
                                let bytes = Array(buffer.readableBytesView)
                                await self?.receive(bytes, gen: gen)
                            }
                        }
                        // The shell ended (exit, or the Mac closed it). Stop the writer too.
                        try await group.next()
                        group.cancelAll()
                    }
                }
                try? await client.close()
                self?.didEnd(error: nil, gen: gen)
            } catch is CancellationError {
                self?.didEnd(error: nil, gen: gen)
            } catch {
                self?.didEnd(error: error, gen: gen)
            }
        }
    }

    func send(_ bytes: [UInt8]) {
        outbound?.yield(.data(bytes))
    }

    func send(_ text: String) {
        send(Array(text.utf8))
    }

    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0, (cols, rows) != size else { return }
        size = (cols, rows)
        outbound?.yield(.resize(cols: cols, rows: rows))
    }

    func disconnect() {
        outbound?.finish()
        task?.cancel()
        let client = client
        Task { try? await client?.close() }
    }

    /// Back to the password prompt after a failure or a disconnect.
    func reset() {
        disconnect()
        generation += 1
        state = .needsPassword
    }

    private func didConnect(_ client: SSHClient, gen: Int) {
        guard gen == generation else {
            Task { try? await client.close() }
            return
        }
        self.client = client
        state = .connected
    }

    private func receive(_ bytes: [UInt8], gen: Int) {
        guard gen == generation else { return }
        onOutput?(bytes[...])
    }

    private func didEnd(error: Error?, gen: Int) {
        guard gen == generation else { return }
        outbound?.finish()
        outbound = nil
        client = nil
        if let error {
            state = .failed(Self.message(for: error, host: host))
        } else if state != .needsPassword {
            state = .disconnected
        }
    }

    /// Plain messages for the failures people actually hit.
    static func message(for error: Error, host: Host) -> String {
        if let error = error as? LocalizedError, let text = error.errorDescription {
            return text
        }
        if case SSHClientError.allAuthenticationOptionsFailed = error {
            return "The Mac refused the username or password."
        }
        if let error = error as? ChannelError, case .connectTimeout = error {
            return "\(host.hostname) did not answer. The Mac can be asleep, offline, or off Tailscale."
        }
        let text = String(describing: error)
        if text.contains("connectionRefused") || text.contains("Connection refused") {
            return "\(host.hostname) refused the connection. Turn on Remote Login in System Settings > General > Sharing."
        }
        if text.contains("NXDOMAIN") || text.contains("nodename nor servname") || text.contains("unknownHost") {
            return "\(host.hostname) was not found. Check the hostname and that Tailscale is on."
        }
        return "Connection failed: \(text)"
    }
}
