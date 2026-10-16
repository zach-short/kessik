import Foundation
import Network
import Observation
import dnssd

/// Finds computers on this Wi-Fi that accept SSH. A Mac with Remote Login on announces `_ssh._tcp`
/// over Bonjour. Tailscale does not carry Bonjour, so this finds Macs on the same network only.
@MainActor
@Observable
final class MacFinder {
    struct Found: Identifiable, Hashable {
        var id: String { name }
        /// The Mac's computer name, such as "Zach's MacBook Pro".
        var name: String
        /// Its local hostname, such as `Zachs-MacBook-Pro.local`. Nil until Bonjour resolves it.
        var hostname: String?
        var port = 22
    }

    private(set) var found: [Found] = []
    /// Why the search stopped, such as Local Network access turned off.
    private(set) var problem: String?

    @ObservationIgnored private var browser: NWBrowser?

    nonisolated static let serviceType = "_ssh._tcp"

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: "local."), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.update(state) }
        }
        // A Mac shows once per network interface. One row per name is enough.
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names = Set(results.compactMap { result -> String? in
                if case .service(let name, _, _, _) = result.endpoint { return name }
                return nil
            })
            Task { @MainActor in self?.update(names) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    private func update(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            problem = nil
        case .waiting(let error), .failed(let error):
            problem = Self.message(for: error)
        default:
            break
        }
    }

    private func update(_ names: Set<String>) {
        found.removeAll { !names.contains($0.name) }
        for name in names.sorted() where !found.contains(where: { $0.name == name }) {
            found.append(Found(name: name))
            Task {
                guard let (hostname, port) = await Self.resolve(name: name),
                      let index = found.firstIndex(where: { $0.name == name }) else { return }
                found[index].hostname = hostname
                found[index].port = port
            }
        }
    }

    private static func message(for error: NWError) -> String {
        if case .dns(let code) = error, Int(code) == kDNSServiceErr_PolicyDenied {
            return "SSHTerm cannot see the local network. Turn on Local Network for SSHTerm in iOS Settings > Privacy & Security > Local Network."
        }
        return "The search stopped: \(error.localizedDescription)"
    }

    // MARK: Resolve

    /// One DNSServiceResolve call. Its callbacks and the timeout run on `queue`, so `finish` runs once.
    private final class Resolve: @unchecked Sendable {
        let queue = DispatchQueue(label: "SSHTerm.resolve")
        var ref: DNSServiceRef?
        var continuation: CheckedContinuation<(hostname: String, port: Int)?, Never>?

        func finish(_ result: (hostname: String, port: Int)?) {
            guard let continuation else { return }
            self.continuation = nil
            if let ref { DNSServiceRefDeallocate(ref) }
            ref = nil
            continuation.resume(returning: result)
        }
    }

    /// The host and port a Bonjour SSH service points at, such as `Zachs-MacBook-Pro.local` and 22.
    /// Network framework resolves only to IP addresses, which change. The `.local` name does not.
    nonisolated static func resolve(name: String, timeout: TimeInterval = 5) async -> (hostname: String, port: Int)? {
        let job = Resolve()
        return await withCheckedContinuation { continuation in
            job.queue.async {
                job.continuation = continuation
                // The timeout closure keeps `job` alive until the ref is gone, so no callback outlives it.
                let context = Unmanaged.passUnretained(job).toOpaque()
                var ref: DNSServiceRef?
                let error = DNSServiceResolve(&ref, 0, 0, name, serviceType, "local.", { _, _, _, error, _, target, port, _, _, context in
                    guard let context else { return }
                    let job = Unmanaged<Resolve>.fromOpaque(context).takeUnretainedValue()
                    guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let target else { return job.finish(nil) }
                    var hostname = String(cString: target)
                    if hostname.hasSuffix(".") { hostname.removeLast() }
                    job.finish((hostname, Int(UInt16(bigEndian: port))))
                }, context)
                guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let ref else { return job.finish(nil) }
                job.ref = ref
                DNSServiceSetDispatchQueue(ref, job.queue)
                job.queue.asyncAfter(deadline: .now() + timeout) { job.finish(nil) }
            }
        }
    }

    // MARK: Reach

    /// One TCP connection attempt. Its state updates and the timeout run on `queue`, so `finish` runs once.
    private final class Probe: @unchecked Sendable {
        let queue = DispatchQueue(label: "SSHTerm.reach")
        let connection: NWConnection
        var continuation: CheckedContinuation<Bool, Never>?

        init(_ connection: NWConnection) { self.connection = connection }

        func finish(_ reached: Bool) {
            guard let continuation else { return }
            self.continuation = nil
            connection.cancel()
            continuation.resume(returning: reached)
        }
    }

    /// Opens a TCP connection to check that this phone can reach `hostname`, without logging in.
    nonisolated static func canReach(_ hostname: String, port: Int, timeout: TimeInterval = 6) async -> Bool {
        let probe = Probe(NWConnection(host: NWEndpoint.Host(hostname),
                                       port: NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? .ssh,
                                       using: .tcp))
        return await withCheckedContinuation { continuation in
            probe.queue.async {
                probe.continuation = continuation
                // `waiting` means refused or no route. Either way the address does not work now.
                probe.connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: probe.finish(true)
                    case .waiting, .failed, .cancelled: probe.finish(false)
                    default: break
                    }
                }
                probe.connection.start(queue: probe.queue)
                probe.queue.asyncAfter(deadline: .now() + timeout) { probe.finish(false) }
            }
        }
    }
}

/// Asks the Mac for its Tailscale IPv4 address, so a Mac found on Wi-Fi also works away from home.
enum TailscaleAddress {
    /// The CLI inside the Mac app, then one on PATH. If neither answers, any interface with a 100.x address.
    static let command = #"export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; "#
        + #"ts=/Applications/Tailscale.app/Contents/MacOS/Tailscale; [ -x "$ts" ] || ts=$(command -v tailscale); "#
        + #"[ -n "$ts" ] && "$ts" ip -4 2>/dev/null; "#
        + #"ifconfig 2>/dev/null | awk '/inet 100\./ {print $2}'; true"#

    /// The first line in Tailscale's range, 100.64.0.0/10.
    static func parse(_ output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: isTailscale)
    }

    static func isTailscale(_ address: String) -> Bool {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false).map { UInt8($0) }
        guard parts.count == 4, !parts.contains(nil) else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1]!)
    }
}

extension Host {
    /// A Bonjour name, such as `my-mac.local`. It works only on the same Wi-Fi as the Mac.
    var isLocalName: Bool { hostname.lowercased().hasSuffix(".local") }
}
