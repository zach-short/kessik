import Foundation
import Observation
import Citadel
import NIOCore
import NIOSSH

/// The Remote tab's line to Kessik Remote on the Mac. Kessik Remote listens on the Mac's loopback
/// address only, so this opens one channel to it through the SSH connection the Sessions tab
/// keeps open. The SSH login is what lets the phone in: it reads the token file over that login
/// and sends the token first.
@MainActor
@Observable
final class RemoteLink {
    enum State: Equatable {
        case idle
        case connecting
        /// `trusted` is false until the Mac allows Kessik Remote under Accessibility.
        case connected(trusted: Bool)
        case failed(String)
    }

    struct Problem: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static let notInstalled = "Kessik Remote is not set up on this Mac. Run `scripts/kessik remote` in the Kessik folder on the Mac."
    static let notRunning = "Kessik Remote is not running on the Mac. Open it on the Mac, or run `scripts/kessik remote` again."
    static let denied = "Kessik Remote refused the token. Quit Kessik Remote on the Mac, open it again, then tap Retry."
    static let closed = "The connection to Kessik Remote closed."

    /// Prints the token Kessik Remote saved. The quotes keep the space in the folder name.
    static let tokenCommand = "cat \"$HOME/\(RemoteWire.tokenPath)\""

    private(set) var state: State = .idle
    @ObservationIgnored private var channel: Channel?
    @ObservationIgnored private var generation = 0

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    /// The token is 64 hex characters on a line of its own. A shell may print other lines first.
    nonisolated static func token(from output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.count == 64 && $0.allSatisfy(\.isHexDigit) }
    }

    func connect(through link: MacLink) async {
        generation += 1
        let gen = generation
        closeChannel()
        state = .connecting
        do {
            let client = try await link.ensureConnected()
            let token = try await readToken(through: link)
            guard gen == generation else { return }

            let reader = ReplyReader(
                onReply: { [weak self] reply in
                    Task { @MainActor in self?.received(reply, gen: gen) }
                },
                onClose: { [weak self] in
                    Task { @MainActor in self?.channelClosed(gen: gen) }
                }
            )
            let channel: Channel
            do {
                channel = try await client.createDirectTCPIPChannel(
                    using: SSHChannelType.DirectTCPIP(
                        targetHost: "127.0.0.1",
                        targetPort: RemoteWire.port,
                        originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 0)
                    ),
                    initialize: { $0.pipeline.addHandler(reader) }
                )
            } catch {
                throw Problem(message: Self.notRunning)
            }
            guard gen == generation else {
                channel.close(promise: nil)
                return
            }
            self.channel = channel
            write(.auth(token))

            // Kessik Remote answers the token at once. No answer means something else has the port.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, gen == self.generation, self.state == .connecting else { return }
                self.closeChannel()
                self.state = .failed(Self.notRunning)
            }
        } catch {
            guard gen == generation else { return }
            closeChannel()
            let message = (error as? Problem)?.message ?? SSHSession.message(for: error, host: link.host)
            state = .failed(message)
        }
    }

    func disconnect() {
        generation += 1
        closeChannel()
        state = .idle
    }

    /// Sends one command. Nothing goes out until the Mac has accepted the token.
    func send(_ command: RemoteCommand) {
        guard isConnected else { return }
        write(command)
    }

    private func readToken(through link: MacLink) async throws -> String {
        let output: String
        do {
            output = try await link.run(Self.tokenCommand)
        } catch {
            // `cat` fails when the file is not there. A lost connection is a different message.
            if link.state == .connected, !(error is TimedOut) { throw Problem(message: Self.notInstalled) }
            throw error
        }
        guard let token = Self.token(from: output) else { throw Problem(message: Self.notInstalled) }
        return token
    }

    private func write(_ command: RemoteCommand) {
        guard let channel else { return }
        let line = command.line + "\n"
        var buffer = channel.allocator.buffer(capacity: line.utf8.count)
        buffer.writeString(line)
        channel.writeAndFlush(buffer, promise: nil)
    }

    private func received(_ reply: RemoteReply, gen: Int) {
        guard gen == generation else { return }
        switch reply {
        case .hello(_, let trusted):
            state = .connected(trusted: trusted)
        case .trusted(let trusted):
            if isConnected { state = .connected(trusted: trusted) }
        case .denied:
            closeChannel()
            state = .failed(Self.denied)
        }
    }

    private func channelClosed(gen: Int) {
        guard gen == generation else { return }
        channel = nil
        if isConnected || state == .connecting { state = .failed(Self.closed) }
    }

    private func closeChannel() {
        channel?.close(promise: nil)
        channel = nil
    }
}

/// Reads the lines Kessik Remote sends back.
private final class ReplyReader: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private var lines = RemoteLineBuffer()
    private let onReply: @Sendable (RemoteReply) -> Void
    private let onClose: @Sendable () -> Void

    init(onReply: @escaping @Sendable (RemoteReply) -> Void, onClose: @escaping @Sendable () -> Void) {
        self.onReply = onReply
        self.onClose = onClose
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
        guard let found = lines.append(Data(bytes)) else {
            context.close(promise: nil)
            return
        }
        for line in found {
            if let reply = RemoteReply(line: line) { onReply(reply) }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        onClose()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
