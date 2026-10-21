import Foundation

import Citadel
import NIOCore
import NIOPosix

/// On an IPv6-only cellular network, such as T-Mobile's, `getaddrinfo` turns an IPv4 literal into a
/// NAT64 IPv6 address. That address leaves over cellular, outside the Tailscale tunnel, so a Mac at
/// its Tailscale address never sees the connection and the login waits. A Tailscale address is
/// reachable only through the tunnel, so it connects as a plain IPv4 socket address, which the
/// tunnel's route carries. Every other host keeps the resolver: a public IPv4 address on such a
/// network needs the NAT64 address.
enum TailscaleSocket {
    /// The address to connect to without the resolver, or nil to resolve `host` as usual.
    static func address(for host: String, port: Int) -> SocketAddress? {
        guard TailscaleAddress.isTailscale(host) else { return nil }
        return try? SocketAddress(ipAddress: host, port: port)
    }
}

extension SSHClient {
    /// `connect(to:)`, except that a Tailscale address skips the resolver. See `TailscaleSocket`.
    static func open(_ settings: SSHClientSettings) async throws -> SSHClient {
        guard let address = TailscaleSocket.address(for: settings.host, port: settings.port) else {
            return try await connect(to: settings)
        }
        // Citadel's own bootstrap sets TCP_NODELAY too, so each keystroke goes out at once.
        let channel = try await ClientBootstrap(group: settings.group)
            .connectTimeout(settings.connectTimeout)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .connect(to: address)
            .get()
        do {
            return try await connect(on: channel, settings: settings)
        } catch {
            try? await channel.close()
            throw error
        }
    }
}
