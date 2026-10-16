import Foundation
import Network
import Observation
import Citadel

/// Watches the phone's network so a dead connection is checked right after a network change,
/// and so a failure can say "this phone is offline" instead of blaming the Mac.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true
    /// Bumped on every path change, such as Wi-Fi to cellular.
    private(set) var changes = 0

    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "sshterm.network"))
    }

    private func update(online: Bool) {
        isOnline = online
        changes += 1
    }
}

struct TimedOut: Error {}

/// The connection ended while the shell was open.
struct ConnectionLost: Error {}

/// Runs `operation`, or throws `TimedOut` after `seconds`. It does not wait for a stuck operation
/// to notice the cancel, because a read on a dead socket never returns.
func withTimeout<T>(_ seconds: Double, _ operation: @escaping () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let once = ResumeOnce(continuation)
        let work = Task {
            do {
                once.resume(with: .success(try await operation()))
            } catch {
                once.resume(with: .failure(error))
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            work.cancel()
            once.resume(with: .failure(TimedOut()))
        }
    }
}

private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

extension SSHClient {
    /// Runs `true` on the Mac. After sleep or a network change the socket can look open while
    /// nothing arrives, so only a reply proves the connection works.
    func isAlive(timeout: Double = 6) async -> Bool {
        guard isConnected else { return false }
        do {
            _ = try await withTimeout(timeout) { try await self.executeCommand("true") }
            return true
        } catch is TimedOut {
            return false
        } catch {
            return isConnected
        }
    }
}
