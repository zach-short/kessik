import Foundation
import Observation
import Citadel
import NIOCore
import NIOSSH
import NIOPosix

/// One interactive shell over SSH. Bytes from the Mac go to `onOutput`;
/// keystrokes and resizes go in through `send` and `resize`, in order.
@MainActor
@Observable
final class SSHSession {
    enum State: Equatable {
        case needsPassword
        case connecting
        case connected
        /// The shell ended on its own, such as `exit` or a tmux detach.
        case disconnected
        /// The connection died while the shell was open.
        case dropped(String)
        /// The connection never opened.
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
    /// Set when the terminal borrows the Sessions tab's connection. It is not closed here.
    @ObservationIgnored private let link: MacLink?
    /// Typed into the shell once it opens.
    @ObservationIgnored private var startCommand: String?
    /// The tmux session a reconnect attaches to again. Without one, a reconnect opens a plain shell.
    @ObservationIgnored private let tmuxName: String?
    @ObservationIgnored private var probing = false
    @ObservationIgnored private var size = (cols: 80, rows: 24)
    /// Bumped on each connect so a late callback from an old connection is ignored.
    @ObservationIgnored private var generation = 0

    init(host: Host) {
        self.host = host
        self.link = nil
        self.startCommand = nil
        self.tmuxName = nil
    }

    init(link: MacLink, startCommand: String, tmuxName: String?) {
        self.host = link.host
        self.link = link
        self.startCommand = startCommand
        self.tmuxName = tmuxName
        state = .connecting
    }

    var ownsClient: Bool { link == nil }

    /// `password` nil means the key and the saved password only. `remember` saves a typed password
    /// once the login works, or removes a saved one.
    func connect(password: String?, remember: Bool = true) {
        let host = host
        let typed = password
        let password = password ?? SavedPassword.get(for: host)
        open {
            let client = try await SSHClient.connect(to: host, password: password)
            if let typed {
                if remember { SavedPassword.save(typed, for: host) } else { SavedPassword.remove(for: host) }
            }
            return client
        }
    }

    /// Opens the shell on the shared connection.
    func start() {
        guard let link else { return }
        state = .needsPassword
        open { try await link.ensureConnected() }
    }

    /// One tap after a drop. A tmux terminal attaches to the same session again; a plain shell
    /// logs in again with the key or saved password, or asks for the password.
    func reconnect() {
        disconnect()
        generation += 1
        state = .needsPassword
        if let link {
            // A snippet command does not run again on its own after a drop.
            startCommand = tmuxName.map(Tmux.attachCommand)
            open { try await link.ensureConnected(verify: true) }
        } else if Credentials.available(for: host) {
            connect(password: nil)
        }
    }

    /// Checks that the Mac still answers, and ends the shell if it does not. The Sessions tab's
    /// link checks shared connections, so this covers only a terminal's own connection.
    func checkAlive() {
        guard ownsClient, state == .connected, !probing, let client else { return }
        probing = true
        let gen = generation
        Task { [weak self] in
            let alive = await client.isAlive()
            guard let self else { return }
            probing = false
            if !alive, gen == generation { Task { try? await client.close() } }
        }
    }

    private func open(_ makeClient: @escaping @MainActor () async throws -> SSHClient) {
        guard state != .connecting, state != .connected else { return }
        state = .connecting
        generation += 1
        let gen = generation

        let (stream, continuation) = AsyncStream<Outbound>.makeStream()
        outbound = continuation
        if let startCommand {
            continuation.yield(.data(Array((startCommand + "\n").utf8)))
        }
        let size = size
        let ownsClient = ownsClient

        task = Task { [weak self] in
            do {
                let client = try await makeClient()
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
                // The shell closed. If the connection went with it, the Mac or the network dropped it.
                let alive = client.isConnected
                if ownsClient { try? await client.close() }
                self?.didEnd(error: alive ? nil : ConnectionLost(), gen: gen)
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
        guard ownsClient else { return }
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
            if ownsClient { Task { try? await client.close() } }
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
            // Once the shell was open, the cause is a lost connection, whatever error NIO reports.
            if state == .connected {
                state = .dropped(Self.message(for: ConnectionLost(), host: host))
            } else {
                state = .failed(Self.message(for: error, host: host))
            }
        } else if state != .needsPassword {
            state = .disconnected
        }
    }

    /// Plain messages for the failures people actually hit.
    static func message(for error: Error, host: Host) -> String {
        let name = host.hostname
        if !NetworkMonitor.shared.isOnline {
            return "This phone is offline. Connect to Wi-Fi or cellular data, then try again."
        }
        if let error = error as? LocalizedError, let text = error.errorDescription {
            return text
        }
        switch error {
        case SSHClientError.allAuthenticationOptionsFailed:
            return "The Mac refused the login. Check the username and password, or add this phone's key to the Mac in Settings."
        case is TimedOut:
            return "\(name) stopped answering. The Mac can be asleep, or the network changed."
        case is ConnectionLost:
            return "The connection to \(name) was lost. The Mac can be asleep, or the network changed."
        default:
            break
        }
        // NIO wraps each address it tried. A DNS failure with no attempts means the name is unknown.
        if let error = error as? NIOConnectionError {
            if let first = error.connectionErrors.first {
                return message(for: first.error, host: host)
            }
            if error.dnsAError != nil || error.dnsAAAAError != nil {
                return "\(name) was not found. Check the hostname, and check that Tailscale is running on this phone."
            }
        }
        if let error = error as? ChannelError {
            switch error {
            case .connectTimeout:
                return "\(name) did not answer. The Mac can be asleep, offline, or off Tailscale."
            case .ioOnClosedChannel, .alreadyClosed, .eof, .outputClosed, .inputClosed:
                return "The connection to \(name) closed."
            default:
                break
            }
        }
        if let error = error as? IOError {
            switch error.errnoCode {
            case ECONNREFUSED:
                return "\(name) refused the connection. Turn on Remote Login in System Settings > General > Sharing."
            case ETIMEDOUT, EHOSTUNREACH, EHOSTDOWN:
                return "\(name) did not answer. The Mac can be asleep, offline, or off Tailscale."
            case ENETUNREACH, ENETDOWN:
                return "This phone has no route to \(name). Check that Tailscale is running on this phone."
            case ECONNRESET, EPIPE:
                return "The connection to \(name) was lost. The Mac can be asleep, or the network changed."
            default:
                break
            }
        }
        let text = String(describing: error)
        if text.contains("connectionRefused") || text.contains("Connection refused") {
            return "\(name) refused the connection. Turn on Remote Login in System Settings > General > Sharing."
        }
        if text.contains("NXDOMAIN") || text.contains("nodename nor servname") || text.contains("unknownHost") {
            return "\(name) was not found. Check the hostname, and check that Tailscale is running on this phone."
        }
        return "Connection failed: \(text)"
    }
}
