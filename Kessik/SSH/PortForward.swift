import Foundation
import Citadel
import NIOCore
import NIOPosix
import NIOSSH

/// Forwards a port on this phone to a port on the Mac's localhost, through the SSH connection
/// that is already open. The phone's browser can then open a dev server that listens only on the Mac.
final class PortForward: @unchecked Sendable {
    struct NothingListening: LocalizedError {
        let port: Int
        var errorDescription: String? {
            "Nothing on the Mac listens on port \(port). Start the dev server, then try again."
        }
    }

    let remotePort: Int
    /// The same number as `remotePort` when it is free on the phone, else one iOS picks.
    let localPort: Int
    private let server: Channel

    var url: URL { URL(string: "http://localhost:\(localPort)")! }

    private init(remotePort: Int, localPort: Int, server: Channel) {
        self.remotePort = remotePort
        self.localPort = localPort
        self.server = server
    }

    static func start(client: SSHClient, remotePort: Int) async throws -> PortForward {
        // One channel first, so a port with no server gives a message instead of a blank browser.
        do {
            let probe = try await openRemote(client: client, port: remotePort) { $0.eventLoop.makeSucceededVoidFuture() }
            try? await probe.close()
        } catch {
            throw NothingListening(port: remotePort)
        }

        let bootstrap = ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { local in
                // The local socket is registered, and starts reading, only once the Mac side is open.
                let remote = local.eventLoop.makePromise(of: Channel.self)
                remote.completeWithTask {
                    try await openRemote(client: client, port: remotePort) { $0.pipeline.addHandler(Relay(peer: local)) }
                }
                return remote.futureResult.flatMap { local.pipeline.addHandler(Relay(peer: $0)) }
            }

        let server: Channel
        do {
            server = try await bootstrap.bind(host: "127.0.0.1", port: remotePort).get()
        } catch {
            server = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        }
        return PortForward(remotePort: remotePort, localPort: server.localAddress?.port ?? remotePort, server: server)
    }

    /// "localhost" lets sshd try both 127.0.0.1 and ::1, since some dev servers listen on only one.
    private static func openRemote(client: SSHClient, port: Int,
                                   initialize: @escaping (Channel) -> EventLoopFuture<Void>) async throws -> Channel {
        try await client.createDirectTCPIPChannel(
            using: SSHChannelType.DirectTCPIP(
                targetHost: "localhost",
                targetPort: port,
                originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 0)
            ),
            initialize: initialize
        )
    }

    func stop() {
        server.close(promise: nil)
    }
}

/// Copies bytes read on one channel to its peer, and closes the peer when this side ends.
private final class Relay: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let peer: Channel

    init(peer: Channel) {
        self.peer = peer
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        peer.writeAndFlush(unwrapInboundIn(data), promise: nil)
    }

    /// The SSH side allows half-closure: the dev server finished its reply, so the browser gets
    /// end of stream after the last byte instead of a reset.
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, event == .inputClosed {
            let peer = peer
            peer.close(mode: .output).whenFailure { _ in peer.close(promise: nil) }
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        peer.close(promise: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
