import XCTest
@testable import Kessik

final class AssistantTests: XCTestCase {
    private let job = Assistant.JobSpec(id: 12, session: "job-12", repo: "kessik", path: "/Users/me/Developer/zach-short/kessik",
                                        tier: "Default", model: "opus", task: "Simplify the settings screen.")

    func testRequestLineIsVerbNumbersThenBase64url() throws {
        let line = try AssistantRequest.line("conv", [3, 40])
        XCTAssertEqual(line, "conv 3 40")
        let send = try AssistantRequest.line("send", payload: ["text": "hi; rm -rf ~ && echo $HOME"])
        let parts = send.split(separator: " ")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], "send")
        XCTAssertNil(parts[1].rangeOfCharacter(from: CharacterSet(charactersIn: "+/=;&$ ")))
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        let back = try JSONSerialization.jsonObject(with: Data(base64Encoded: b64)!) as? [String: String]
        XCTAssertEqual(back?["text"], "hi; rm -rf ~ && echo $HOME")
    }

    func testRequestLineRejectsUnknownVerbsAndNegativeNumbers() {
        XCTAssertThrowsError(try AssistantRequest.line("shell"))
        XCTAssertThrowsError(try AssistantRequest.line("conv", [-1]))
    }

    func testDecodeReadsTheLastJSONLineAndRaisesRefusals() throws {
        let ok = try AssistantLink.decode(AssistantReply.Ping.self, from: "motd line\n{\"ok\": true, \"version\": 1, \"facts\": 2, \"repos\": 3}\n")
        XCTAssertEqual(ok.repos, 3)
        XCTAssertThrowsError(try AssistantLink.decode(AssistantReply.Ping.self, from: #"{"ok": false, "error": "ValueError: no"}"#)) { error in
            XCTAssertEqual((error as? AssistantLink.Refused)?.message, "ValueError: no")
        }
        XCTAssertThrowsError(try AssistantLink.decode(AssistantReply.Ping.self, from: "Permission denied"))
    }

    func testSnakeCaseRepliesDecode() throws {
        let json = #"{"ok": true, "messages": [{"id": 5, "role": "card", "text": "", "card_id": 9, "created_at": "2026-11-07T10:00:00-05:00", "card": {"id": 9, "conv_id": 1, "repo": "kessik", "path": "/Users/me/k", "tier": "Light", "task": "x", "warnings": ["The task holds an email address."], "status": "proposed", "last_event": null, "created_at": "a", "updated_at": "b"}}], "turn": {"id": 2, "conv_id": 1, "status": "running", "error": null, "created_at": "a", "finished_at": null}}"#
        let r = try AssistantLink.decode(AssistantReply.Conv.self, from: json)
        XCTAssertEqual(r.messages.first?.card?.warnings.count, 1)
        XCTAssertEqual(r.messages.first?.cardId, 9)
        XCTAssertTrue(r.turn?.isRunning == true)
    }

    func testJobArgumentsAreModelHooksThenTask() throws {
        let args = try JobStart.claudeArguments(for: job, home: "/Users/me")
        XCTAssertEqual(args[0], "--model")
        XCTAssertEqual(args[1], "opus")
        XCTAssertEqual(args[2], "--settings")
        XCTAssertEqual(args.last, job.task)
        let settings = try JSONSerialization.jsonObject(with: Data(args[3].utf8)) as? [String: Any]
        let hooks = settings?["hooks"] as? [String: Any]
        XCTAssertEqual(Set(hooks.map { Array($0.keys) } ?? []), ["UserPromptSubmit", "Stop", "Notification", "SessionEnd"])
        XCTAssertTrue(args[3].contains("/Users/Shared/home-agent/bin/job-event 12 stop"))
    }

    func testJobChecksRejectBadFields() {
        var bad = job; bad.model = "gpt"
        XCTAssertThrowsError(try JobStart.claudeArguments(for: bad, home: "/Users/me"))
        bad = job; bad.session = "job-13"
        XCTAssertThrowsError(try JobStart.claudeArguments(for: bad, home: "/Users/me"))
        bad = job; bad.path = "/Users/me/../other/repo"
        XCTAssertThrowsError(try JobStart.claudeArguments(for: bad, home: "/Users/me"))
        bad = job; bad.path = "/etc"
        XCTAssertThrowsError(try JobStart.claudeArguments(for: bad, home: "/Users/me"))
        XCTAssertThrowsError(try JobStart.claudeArguments(for: job, home: ""))
    }

    func testJobStartQuotesTheTask() {
        var risky = job; risky.task = "Fix it'; rm -rf ~; echo '"
        let args = try! JobStart.claudeArguments(for: risky, home: "/Users/me")
        let script = Tmux.startDetachedScript(name: risky.session, path: risky.path, claudeArguments: args)
        XCTAssertTrue(script.contains(#"claude --remote-control 'job-12' '--model' 'opus' '--settings'"#))
        XCTAssertTrue(script.contains(#"'Fix it'\''; rm -rf ~; echo '\'''"#))
    }

    func testDefaultStartIsUnchanged() {
        XCTAssertTrue(Tmux.startDetachedScript(name: "app", path: "/Users/me/app").contains("claude --remote-control 'app'\n"))
    }

    func testReposParseKeepsHomeAndDropsDuplicates() {
        let out = "/Users/me\n/Users/me/Developer/zach-short/kessik\n/Users/me/Developer/old/kessik\n/Users/me/Developer/x/bad name\n/tmp/evil\n"
        let parsed = JobStart.parseRepos(out)
        XCTAssertEqual(parsed?.home, "/Users/me")
        XCTAssertEqual(parsed?.repos.map { $0["name"] }, ["kessik"])
    }

    func testAssistantTabIsHiddenUntilTurnedOn() {
        XCTAssertFalse(AppTab.visible(assistant: false).contains(.assistant))
        XCTAssertEqual(AppTab.visible(assistant: true), [.hosts, .sessions, .assistant, .settings])
    }
}
