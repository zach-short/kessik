import XCTest
@testable import Kessik

final class SnippetTransferTests: XCTestCase {
    private let mine = [
        Snippet(label: "Yes", text: "yes", kind: .reply),
        Snippet(label: "Logs", text: "tail -f log", kind: .command),
    ]

    private func file(_ snippets: String, version: Int = 1, format: String = "kessik-snippets") -> Data {
        Data(#"{"format":"\#(format)","version":\#(version),"snippets":\#(snippets)}"#.utf8)
    }

    private func entry(_ label: String, _ text: String, _ kind: String = "reply") -> [String: String] {
        ["label": label, "text": text, "kind": kind]
    }

    private func file(entries: [[String: String]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["format": "kessik-snippets", "version": 1, "snippets": entries])
    }

    private func XCTAssertThrows(_ data: Data, _ expected: SnippetTransfer.ImportError,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try SnippetTransfer.decode(data), file: file, line: line) {
            XCTAssertEqual($0 as? SnippetTransfer.ImportError, expected, file: file, line: line)
        }
    }

    func testRoundTripKeepsLabelTextKindAndOrder() throws {
        let decoded = try SnippetTransfer.decode(try SnippetTransfer.encode(mine))
        XCTAssertEqual(decoded.map(\.label), ["Yes", "Logs"])
        XCTAssertEqual(decoded.map(\.text), ["yes", "tail -f log"])
        XCTAssertEqual(decoded.map(\.kind), [.reply, .command])
        XCTAssertNotEqual(decoded.map(\.id), mine.map(\.id), "Each phone makes its own ids.")
    }

    func testExportHoldsOnlyFormatVersionAndSnippetFields() throws {
        let object = try JSONSerialization.jsonObject(with: try SnippetTransfer.encode(mine)) as? [String: Any]
        XCTAssertEqual(Set((object ?? [:]).keys), ["format", "version", "snippets"])
        XCTAssertEqual(object?["version"] as? Int, SnippetTransfer.version)
        let first = (object?["snippets"] as? [[String: Any]])?.first
        XCTAssertEqual(Set((first ?? [:]).keys), ["label", "text", "kind"])
    }

    func testMergeKeepsMineAndSkipsExactCopies() throws {
        let imported = try SnippetTransfer.decode(try file(entries: [
            entry("Yes", "yes"),
            entry("Yes", "yes!"),
            entry("Logs", "tail -f log", "command"),
            entry("Logs", "tail -f log"),
            entry("Yes", "yes!"),
        ]))
        XCTAssertEqual(imported.count, 4, "Copies inside the file collapse.")
        let merged = SnippetTransfer.combine(mine, with: imported, mode: .merge)
        XCTAssertEqual(merged.map(\.text), ["yes", "yes!", "tail -f log", "tail -f log"])
        XCTAssertEqual(merged.map(\.kind), [.reply, .reply, .reply, .command])
        XCTAssertEqual(merged.first?.id, mine[0].id)
        XCTAssertEqual(merged.last?.id, mine[1].id)
    }

    func testReplaceDropsMine() throws {
        let imported = try SnippetTransfer.decode(try file(entries: [entry("Go", "go", "command"), entry("Ok", "ok")]))
        let replaced = SnippetTransfer.combine(mine, with: imported, mode: .replace)
        XCTAssertEqual(replaced.map(\.label), ["Ok", "Go"], "Grouped by kind, replies first.")
        XCTAssertFalse(replaced.contains { mine.map(\.id).contains($0.id) })
    }

    func testRejectsFileThatIsNotJSON() {
        XCTAssertThrows(Data("not json {".utf8), .notJSON)
        XCTAssertThrows(Data([0xFF, 0xFE, 0x00]), .notJSON)
        XCTAssertThrows(Data(), .notJSON)
    }

    func testRejectsJSONThatIsNotASnippetFile() {
        XCTAssertThrows(Data("[1, 2]".utf8), .notSnippetFile)
        XCTAssertThrows(file("[]", format: "termius"), .notSnippetFile)
        XCTAssertThrows(file(#""many""#), .notSnippetFile)
        XCTAssertThrows(file("[]", version: 0), .notSnippetFile)
    }

    func testRejectsNewerVersion() {
        XCTAssertThrows(file(#"[{"label":"a","text":"a","kind":"reply"}]"#, version: 2), .newerVersion(2))
        XCTAssertThrows(Data(#"{"format":"kessik-snippets","version":99,"items":{}}"#.utf8), .newerVersion(99))
    }

    func testRejectsFileWithNoUsableSnippets() {
        XCTAssertThrows(file("[]"), .empty)
        XCTAssertThrows(file(#"[{"label":"a","text":"   ","kind":"reply"}, {"text":"x","kind":"macro"}, 7, null]"#), .empty)
    }

    func testRejectsOversizedFileAndTooManySnippets() throws {
        XCTAssertThrows(Data(repeating: 0x20, count: SnippetTransfer.maxFileBytes + 1), .tooLarge)
        let many = Array(repeating: entry("a", "a"), count: SnippetTransfer.maxSnippets + 1)
        XCTAssertThrows(try file(entries: many), .tooMany)
    }

    func testDropsHugeTextAndCutsLongLabel() throws {
        let decoded = try SnippetTransfer.decode(try file(entries: [
            entry("big", String(repeating: "x", count: SnippetTransfer.maxTextLength + 1)),
            entry(String(repeating: "L", count: 10_000), "ok"),
        ]))
        XCTAssertEqual(decoded.map(\.text), ["ok"])
        XCTAssertEqual(decoded.first?.label.count, SnippetTransfer.maxLabelLength)
    }

    func testEmptyLabelBecomesTheText() throws {
        let decoded = try SnippetTransfer.decode(file(#"[{"label":" ","text":" ls -la ","kind":"command"}, {"text":"yes","kind":"reply"}]"#))
        XCTAssertEqual(decoded.map(\.label), ["yes", "ls -la"])
        XCTAssertEqual(decoded.map(\.text), ["yes", "ls -la"])
    }

    func testStripsControlCharactersButKeepsNewLinesAndEmoji() throws {
        let decoded = try SnippetTransfer.decode(try file(entries: [
            entry("Bad\u{1b}[2J\nlabel\u{202E}", "echo a\u{1b}]0;x\u{07}\r\nrm\u{0}\u{7f} b\tc", "command"),
            entry("Family 👨‍👩‍👧", "\u{1b}\u{08}"),
        ]))
        XCTAssertEqual(decoded.count, 1, "A text of only control characters is dropped.")
        XCTAssertEqual(decoded[0].label, "Bad[2J label")
        XCTAssertEqual(decoded[0].text, "echo a]0;x\nrm b\tc")
        let emoji = try SnippetTransfer.decode(try file(entries: [entry("Family 👨‍👩‍👧", "ok")]))
        XCTAssertEqual(emoji.first?.label, "Family 👨‍👩‍👧")
    }

    func testWrongFieldTypesDropOnlyThatEntry() throws {
        let decoded = try SnippetTransfer.decode(file(#"[{"label":1,"text":"a","kind":"reply"}, {"label":"b","text":["x"],"kind":"reply"}, "str"]"#))
        XCTAssertEqual(decoded.map(\.label), ["a"])
    }

    func testReadsAPickedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        try SnippetTransfer.encode(mine).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try SnippetTransfer.read(url).map(\.text), ["yes", "tail -f log"])
    }
}
