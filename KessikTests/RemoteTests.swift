import XCTest
@testable import Kessik

final class RemoteTests: XCTestCase {
    func testEveryCommandSurvivesTheWire() {
        var commands: [RemoteCommand] = [
            .auth(String(repeating: "ab", count: 32)),
            .move(dx: 12.5, dy: -3),
            .scroll(dx: 0, dy: -40.2),
            .text("héllo wörld 👋"),
            .text(" "),
        ]
        for button in RemoteButton.allCases {
            for press in RemotePress.allCases { commands.append(.button(button, press)) }
        }
        commands += RemoteKey.allCases.map(RemoteCommand.key)
        commands += RemoteAction.allCases.map(RemoteCommand.action)

        for command in commands {
            XCTAssertEqual(RemoteCommand(line: command.line), command, command.line)
            XCTAssertFalse(command.line.contains("\n"))
        }
    }

    func testMoveKeepsOneDecimal() {
        XCTAssertEqual(RemoteCommand.move(dx: 1.26, dy: -0.04).line, "m 1.3 -0.0")
    }

    func testBadLinesAreRefused() {
        for line in ["", "m", "m 1", "m 1 nan", "m 1 inf", "m a b", "b left hold", "b middle click",
                     "k f13", "a reboot", "t not base64!", "auth", "auth a b", "x 1 2"] {
            XCTAssertNil(RemoteCommand(line: line), line)
        }
    }

    func testReplies() {
        XCTAssertEqual(RemoteReply(line: "hello 1 0"), .hello(version: 1, trusted: false))
        XCTAssertEqual(RemoteReply(line: "hello 2 1"), .hello(version: 2, trusted: true))
        XCTAssertEqual(RemoteReply(line: "ax 1"), .trusted(true))
        XCTAssertEqual(RemoteReply(line: "denied"), .denied)
        for reply in [RemoteReply.hello(version: 1, trusted: true), .trusted(false), .denied] {
            XCTAssertEqual(RemoteReply(line: reply.line), reply)
        }
        for line in ["", "hello", "hello 1", "hello 1 yes", "ax", "ax 2", "denied now"] {
            XCTAssertNil(RemoteReply(line: line), line)
        }
    }

    func testLineBufferJoinsSplitLines() {
        var buffer = RemoteLineBuffer()
        XCTAssertEqual(buffer.append(Data("hel".utf8)), [])
        XCTAssertEqual(buffer.append(Data("lo 1 1\nax".utf8)), ["hello 1 1"])
        XCTAssertEqual(buffer.append(Data(" 0\r\nax 1\n".utf8)), ["ax 0", "ax 1"])
    }

    func testLineBufferRefusesAnEndlessLine() {
        var buffer = RemoteLineBuffer()
        XCTAssertNil(buffer.append(Data(repeating: 0x61, count: RemoteLineBuffer.limit + 1)))
    }

    func testTokenIsTheLastHexLine() {
        let token = String(repeating: "0f", count: 32)
        XCTAssertEqual(RemoteLink.token(from: "Last login: today\n\(token)\n"), token)
        XCTAssertEqual(RemoteLink.token(from: token), token)
        XCTAssertNil(RemoteLink.token(from: ""))
        XCTAssertNil(RemoteLink.token(from: "cat: token: No such file or directory\n"))
        XCTAssertNil(RemoteLink.token(from: String(repeating: "zz", count: 32)))
        XCTAssertNil(RemoteLink.token(from: String(token.dropLast())))
    }

    func testRemoteTabHidesUntilSettingsTurnsItOn() {
        XCTAssertFalse(AppTab.visible(assistant: true).contains(.remote))
        XCTAssertEqual(AppTab.visible(assistant: false, remote: true), [.hosts, .sessions, .remote, .settings])
        XCTAssertEqual(AppTab.visible(assistant: true, remote: true), AppTab.allCases)
    }

    func testAFastFingerMovesThePointerFarther() {
        let slow = TrackpadMotion.pointer(dx: 1, dy: 0)
        let fast = TrackpadMotion.pointer(dx: 20, dy: 0)
        XCTAssertGreaterThan(slow.dx, 1)
        XCTAssertLessThan(slow.dx, 2)
        XCTAssertGreaterThan(fast.dx / 20, slow.dx)
        // The gain stops growing, so one wild sample cannot throw the pointer off the screen.
        XCTAssertEqual(TrackpadMotion.pointer(dx: 300, dy: 0).dx / 300, TrackpadMotion.pointer(dx: 30, dy: 0).dx / 30, accuracy: 0.0001)
        XCTAssertEqual(TrackpadMotion.pointer(dx: 0, dy: -4).dx, 0)
        XCTAssertLessThan(TrackpadMotion.pointer(dx: 0, dy: -4).dy, -4)
    }
}
