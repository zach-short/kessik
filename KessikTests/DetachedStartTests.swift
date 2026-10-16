import XCTest
@testable import Kessik

final class DetachedStartTests: XCTestCase {
    // MARK: The command

    func testScriptStartsTheSessionWithoutAttaching() {
        let script = Tmux.startDetachedScript(name: "app", path: "/Users/me/app")

        XCTAssertTrue(script.contains("tmux new-session -d -s 'app' -c '/Users/me/app' claude --remote-control 'app'"))
        XCTAssertFalse(script.contains("attach"))
        XCTAssertFalse(script.contains("exec tmux"))
    }

    func testScriptLeavesAnExistingSessionAlone() throws {
        let script = Tmux.startDetachedScript(name: "app", path: "/Users/me/app")

        // The check comes first, and only its else branch creates a session.
        let check = try XCTUnwrap(script.range(of: "tmux has-session -t '=app' 2>/dev/null; then echo \(Tmux.runningMarker); else"))
        let create = try XCTUnwrap(script.range(of: "tmux new-session"))
        XCTAssertLessThan(check.lowerBound, create.lowerBound)
    }

    func testScriptChecksTheSessionIsStillThereAfterItStarts() {
        let script = Tmux.startDetachedScript(name: "app", path: "/Users/me/app")

        XCTAssertTrue(script.contains("sleep 1; if tmux has-session -t '=app' 2>/dev/null; then echo \(Tmux.startedMarker); else echo \(Tmux.exitedMarker); fi"))
    }

    func testScriptReportsAMissingTmux() {
        let script = Tmux.startDetachedScript(name: "app", path: "/Users/me/app")

        XCTAssertTrue(script.hasPrefix("command -v tmux >/dev/null 2>&1 || { echo \(Tmux.noTmuxMarker); exit 0; }; "))
    }

    func testScriptQuotesAPathWithASingleQuote() {
        let script = Tmux.startDetachedScript(name: "app", path: "/Users/me/it's")

        XCTAssertTrue(script.contains(#"-c '/Users/me/it'\''s' claude"#))
    }

    /// The Mac's own login shell runs the script, so `PATH` is the one from its startup files.
    func testCommandRunsTheScriptInTheLoginShell() {
        let command = Tmux.startDetachedCommand(name: "app", path: "/Users/me/it's")

        let prefix = #""${SHELL:-/bin/sh}" -ilc "#
        XCTAssertTrue(command.hasPrefix(prefix))
        XCTAssertEqual(unquote(String(command.dropFirst(prefix.count))),
                       Tmux.startDetachedScript(name: "app", path: "/Users/me/it's"))
    }

    // MARK: The result

    func testParsesEachMarker() {
        XCTAssertEqual(Tmux.parseStart(Tmux.startedMarker + "\n"), .started)
        XCTAssertEqual(Tmux.parseStart(Tmux.runningMarker + "\n"), .alreadyRunning)
        XCTAssertEqual(Tmux.parseStart(Tmux.exitedMarker + "\n"), .exitedAtOnce)
        XCTAssertEqual(Tmux.parseStart(Tmux.noTmuxMarker + "\n"), .noTmux)
    }

    /// An interactive shell can print other lines first, such as a tty warning from zsh.
    func testParsesAMarkerAfterShellNoise() {
        let output = "zsh: can't set tty process group (4242): Inappropriate ioctl for device\n\(Tmux.startedMarker)\n"

        XCTAssertEqual(Tmux.parseStart(output), .started)
    }

    func testNoMarkerIsNil() {
        XCTAssertNil(Tmux.parseStart(""))
        XCTAssertNil(Tmux.parseStart("can't find directory: /Users/me/gone\n"))
    }

    // MARK: Helpers

    /// Reads one single-quoted shell word back to its text.
    private func unquote(_ word: String) -> String {
        XCTAssertTrue(word.hasPrefix("'") && word.hasSuffix("'"), "not one quoted word: \(word)")
        return String(word.dropFirst().dropLast()).replacingOccurrences(of: #"'\''"#, with: "'")
    }
}
