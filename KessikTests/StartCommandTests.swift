import XCTest
@testable import Kessik

final class StartCommandTests: XCTestCase {
    private let mouse = #" \; set -t '=app:' mouse on"#

    private func mac(startCommand: String?) -> Host {
        Host(name: "Mac", hostname: "mac.tailnet.ts.net", username: "user", startCommand: startCommand)
    }

    func testDefaultCommandIsUnchanged() {
        XCTAssertEqual(Tmux.newClaudeCommand(name: "app", path: "/Users/me/app"),
                       "exec tmux new -A -s 'app' -c '/Users/me/app' claude --remote-control 'app'" + mouse)
    }

    func testCustomCommandIsOneQuotedString() {
        XCTAssertEqual(Tmux.newClaudeCommand(name: "app", path: "/Users/me/app", startCommand: "claude --model opus"),
                       "exec tmux new -A -s 'app' -c '/Users/me/app' 'claude --model opus'" + mouse)
    }

    func testCustomCommandWithSingleQuote() {
        XCTAssertEqual(Tmux.newClaudeCommand(name: "app", path: "/Users/me/app", startCommand: "codex 'fix it'"),
                       #"exec tmux new -A -s 'app' -c '/Users/me/app' 'codex '\''fix it'\'''"# + mouse)
    }

    func testBlankCommandIsDefault() {
        XCTAssertNil(mac(startCommand: nil).customStartCommand)
        XCTAssertNil(mac(startCommand: "").customStartCommand)
        XCTAssertNil(mac(startCommand: "   ").customStartCommand)
        XCTAssertEqual(mac(startCommand: "  codex ").customStartCommand, "codex")
        XCTAssertEqual(Tmux.newClaudeCommand(name: "app", path: "/Users/me/app",
                                             startCommand: mac(startCommand: " ").customStartCommand),
                       Tmux.newClaudeCommand(name: "app", path: "/Users/me/app"))
    }

    /// A Mac as builds before start commands saved it, with no `startCommand` key.
    func testOldHostJSONDecodesWithoutStartCommand() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Mac","hostname":"mac.local",
         "port":22,"username":"user","status":"unknown"}
        """
        let host = try JSONDecoder().decode(Host.self, from: Data(json.utf8))
        XCTAssertNil(host.startCommand)
        XCTAssertNil(host.customStartCommand)
    }

    func testStartCommandRoundTripsThroughJSON() throws {
        let host = mac(startCommand: "codex")
        let decoded = try JSONDecoder().decode(Host.self, from: JSONEncoder().encode(host))
        XCTAssertEqual(decoded.startCommand, "codex")
    }
}
