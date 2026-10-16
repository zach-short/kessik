import XCTest
@testable import Kessik

final class DetachedStartTests: XCTestCase {
    private func script(_ name: String = "app", _ path: String = "/Users/me/app") -> String {
        Tmux.startDetachedScript(name: name, path: path)
    }

    // MARK: The command

    func testScriptStartsTheSessionWithoutAttaching() {
        let script = script()

        XCTAssertTrue(script.contains("tmux new-session -d -s 'app' -c '/Users/me/app' claude --remote-control 'app'"))
        XCTAssertFalse(script.contains("attach"))
        XCTAssertFalse(script.contains("exec tmux"))
    }

    func testScriptLeavesAnExistingSessionAlone() throws {
        let script = script()

        // The check comes first, and the session is only created when it finds none.
        let check = try XCTUnwrap(script.range(of: "if tmux has-session -t '=app' 2>/dev/null; then\n"))
        let rerun = try XCTUnwrap(script.range(of: "echo \(Tmux.runningMarker); fi; exit 0; fi\n"))
        let create = try XCTUnwrap(script.range(of: "tmux new-session"))
        XCTAssertLessThan(check.lowerBound, rerun.lowerBound)
        XCTAssertLessThan(rerun.lowerBound, create.lowerBound)
    }

    func testScriptReportsAMissingTmux() {
        XCTAssertTrue(script().hasPrefix("command -v tmux >/dev/null 2>&1 || { echo \(Tmux.noTmuxMarker); exit 0; }\n"))
    }

    func testScriptReportsASessionThatEndsAtOnce() {
        // Every pass of the wait checks that the session is still there.
        XCTAssertTrue(script().contains("sleep 0.5\ntmux has-session -t '=app' 2>/dev/null || { echo \(Tmux.exitedMarker); exit 0; }\n"))
    }

    func testScriptQuotesAPathWithASingleQuote() {
        XCTAssertTrue(script("app", "/Users/me/it's").contains(#"-c '/Users/me/it'\''s' claude"#))
    }

    // MARK: The trust question

    /// The text Claude Code v2.1.301 draws in a folder it has not seen, read from a real session.
    private let trustScreen = """
         Accessing workspace:
         /private/tmp/kessik-trusttest
         Quick safety check: Is this a project you created or one you trust? (Like your
         own code, a well-known open source project, or work from your team). If not,
         take a moment to review what's in this folder first.
         Claude Code'll be able to read, edit, and execute files here.
         Security guide
         ❯ No, exit
           Yes, I trust this folder
         Enter to confirm · Esc to cancel
        """

    /// The banner Claude Code v2.1.301 draws when it is ready.
    private let readyScreen = """
         ▐▛███▛█   Claude Code v2.1.301
        ▝▜██████▀  Sonnet 5.5 · Claude Max
         ▝▝   ▝▝   ~/Projects
        ────────────────────────────────────────────────────────────────────────────────
        ❯ Try "fix lint errors"
        """

    func testScriptWatchesForTheTrustQuestionBeforeAndAfterAStart() {
        let script = script()

        // The patterns are in the script, and they match the real screen text and not the ready screen.
        XCTAssertTrue(script.contains(#"*"I trust this folder"*"#))
        XCTAssertTrue(trustScreen.contains("I trust this folder"))
        XCTAssertFalse(readyScreen.contains("I trust this folder"))
        // It is checked for a session that exists and for one that starts.
        XCTAssertEqual(script.components(separatedBy: "if asks; then echo \(Tmux.trustMarker)").count - 1, 2)
    }

    func testScriptTreatsTheBannerAsReady() {
        XCTAssertTrue(script().contains(#"*"Claude Code v"*|*"Welcome to Claude Code"*) echo \#(Tmux.startedMarker); exit 0;; esac"#))
        XCTAssertTrue(readyScreen.contains("Claude Code v"))
        XCTAssertFalse(trustScreen.contains("Claude Code v"))
    }

    func testScriptGivesUpWaitingAfterEightSeconds() {
        let script = script()

        XCTAssertTrue(script.contains("while [ $i -lt 16 ]; do\nsleep 0.5\n"))
        XCTAssertTrue(script.hasSuffix("done\necho \(Tmux.startedMarker)"))
    }

    /// `capture-pane` needs the trailing colon, or tmux finds no session.
    func testScriptReadsThePaneWithTheTrailingColon() {
        XCTAssertTrue(script().contains("tmux capture-pane -p -t '=app:'"))
    }

    // MARK: The login shell

    /// The Mac's login shell supplies `PATH` and hands the script to `sh`.
    func testCommandRunsTheScriptInShFromTheLoginShell() {
        let command = Tmux.startDetachedCommand(name: "app", path: "/Users/me/it's")

        let prefix = #""${SHELL:-/bin/sh}" -ilc "#
        XCTAssertTrue(command.hasPrefix(prefix))
        let inner = unquote(String(command.dropFirst(prefix.count)))
        XCTAssertTrue(inner.hasPrefix("exec /bin/sh -c "))
        XCTAssertEqual(unquote(String(inner.dropFirst("exec /bin/sh -c ".count))), script("app", "/Users/me/it's"))
    }

    // MARK: The result

    func testParsesEachMarker() {
        XCTAssertEqual(Tmux.parseStart(Tmux.startedMarker + "\n"), .started)
        XCTAssertEqual(Tmux.parseStart(Tmux.runningMarker + "\n"), .alreadyRunning)
        XCTAssertEqual(Tmux.parseStart(Tmux.trustMarker + "\n"), .needsTrust)
        XCTAssertEqual(Tmux.parseStart(Tmux.exitedMarker + "\n"), .exitedAtOnce)
        XCTAssertEqual(Tmux.parseStart(Tmux.noTmuxMarker + "\n"), .noTmux)
    }

    /// An interactive shell can print other lines first, such as a tty warning from zsh.
    func testParsesAMarkerAfterShellNoise() {
        let output = "zsh: can't set tty process group (4242): Inappropriate ioctl for device\n\(Tmux.trustMarker)\n"

        XCTAssertEqual(Tmux.parseStart(output), .needsTrust)
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
