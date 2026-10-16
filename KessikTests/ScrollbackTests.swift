import XCTest
@testable import Kessik

final class ScrollbackTests: XCTestCase {
    private let history = Scrollback(output: """
    $ npm test
    Error: cannot find module
    ok 1 - error handling
    ERROR twice error
    done
    """)

    func testCountsEveryMatchNotOnlyLines() {
        let hits = history.search("error")
        XCTAssertEqual(hits.map(\.id), [1, 2, 3])
        XCTAssertEqual(Scrollback.matchCount(hits), 4)
    }

    func testSearchIgnoresCase() {
        XCTAssertEqual(history.search("ERROR").map(\.id), history.search("error").map(\.id))
        XCTAssertEqual(history.search("Npm").map(\.id), [0])
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertTrue(history.search("").isEmpty)
        XCTAssertTrue(Scrollback.occurrences(of: "", in: "abc").isEmpty)
    }

    func testRegexCharactersMatchOnlyThemselves() {
        let text = Scrollback(output: "a.b\naxb\n(x)*\n[1]\n$HOME\n\\d")
        XCTAssertEqual(text.search("a.b").map(\.id), [0])
        XCTAssertEqual(text.search("(x)*").map(\.id), [2])
        XCTAssertEqual(text.search("[1]").map(\.id), [3])
        XCTAssertEqual(text.search("$HOME").map(\.id), [4])
        XCTAssertEqual(text.search("\\d").map(\.id), [5])
        XCTAssertTrue(text.search(".*").isEmpty)
    }

    func testMatchesDoNotOverlap() {
        XCTAssertEqual(Scrollback.occurrences(of: "aa", in: "aaaa").count, 2)
    }

    func testHitsCarryTheLinesAround() {
        let hits = history.search("done")
        XCTAssertEqual(hits.first?.before, ["ERROR twice error"])
        XCTAssertEqual(hits.first?.after, [])
        let first = history.search("npm").first
        XCTAssertEqual(first?.before, [])
        XCTAssertEqual(first?.after, ["Error: cannot find module"])
        XCTAssertEqual(history.search("cannot", context: 2).first?.before, ["$ npm test"])
        XCTAssertEqual(history.search("cannot", context: 2).first?.after, ["ok 1 - error handling", "ERROR twice error"])
    }

    func testNewestMatchIsLast() {
        XCTAssertEqual(history.search("error").last?.line, "ERROR twice error")
    }

    func testTrailingSpacesAndBlankScreenRowsGo() {
        let text = Scrollback(output: "one   \n\ntwo\t\n\n\n   \n")
        XCTAssertEqual(text.lines, ["one", "", "two"])
    }

    func testKeepsOnlyTheNewestLines() {
        let output = (1...20).map(String.init).joined(separator: "\n")
        XCTAssertEqual(Scrollback(output: output, maxLines: 5).lines, ["16", "17", "18", "19", "20"])
    }

    func testSegmentsSplitTheLineAroundMatches() {
        let line = "Error and error"
        let parts = Scrollback.segments(line, ranges: Scrollback.occurrences(of: "error", in: line))
        XCTAssertEqual(parts.map(\.text), ["Error", " and ", "error"])
        XCTAssertEqual(parts.map(\.match), [true, false, true])
        XCTAssertEqual(Scrollback.segments("plain", ranges: []).map(\.text), ["plain"])
    }

    func testCaptureCommandReadsPlainJoinedHistory() {
        let command = Scrollback.captureCommand(session: "kessik")
        XCTAssertTrue(command.hasPrefix(#"export PATH="#))
        XCTAssertTrue(command.hasSuffix("tmux capture-pane -p -J -S -10000 -t '=kessik:'"))
        XCTAssertFalse(command.contains(" -e"))
        XCTAssertTrue(Scrollback.captureCommand(session: "x", lines: 50).contains("-S -50 "))
    }

    func testCaptureCommandQuotesSpacesAndQuotes() {
        let command = Scrollback.captureCommand(session: #"my "app" it's; rm -rf ~"#)
        XCTAssertTrue(command.hasSuffix(#"-t '=my "app" it'\''s; rm -rf ~:'"#))
    }
}
