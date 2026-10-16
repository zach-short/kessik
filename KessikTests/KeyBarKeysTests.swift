import XCTest
import SwiftTerm
@testable import Kessik

final class KeyBarKeysTests: XCTestCase {
    private var suiteName: String!
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "KeyBarKeysTests.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsAreTheOldNineSymbolsInOrder() {
        let old = ["|", "~", "/", "-", "`", "$", "&", "*", "\\"]
        XCTAssertEqual(KeyBarKeys.defaultIDs, old)
        XCTAssertEqual(KeyBarKeys.defaults.map(\.title), old)
        XCTAssertEqual(KeyBarKeys.load(from: store).map(\.id), old)
        for key in KeyBarKeys.defaults {
            XCTAssertEqual(key.bytes(applicationCursor: false), Array(key.id.utf8))
        }
    }

    func testRoundTrip() {
        let ids = ["home", "{", "}", "pageDown", "|"]
        KeyBarKeys.save(ids.compactMap(ExtraKey.with(id:)), to: store)
        XCTAssertEqual(KeyBarKeys.load(from: store).map(\.id), ids)
    }

    func testResetGoesBackToDefaults() {
        KeyBarKeys.save([ExtraKey.with(id: "@")!], to: store)
        KeyBarKeys.reset(in: store)
        XCTAssertEqual(KeyBarKeys.load(from: store).map(\.id), KeyBarKeys.defaultIDs)
    }

    func testCorruptDataFallsBackToDefaults() {
        for bad: Any in [[String](), "|~/", 42, Data([0xff, 0x00]), ["nope", "alsoNope"], [1, 2, 3]] {
            store.set(bad, forKey: KeyBarKeys.defaultsKey)
            XCTAssertEqual(KeyBarKeys.load(from: store).map(\.id), KeyBarKeys.defaultIDs, "\(bad)")
        }
    }

    func testUnknownIDsAndRepeatsAreDropped() {
        store.set(["|", "bogus", "|", "end"], forKey: KeyBarKeys.defaultsKey)
        XCTAssertEqual(KeyBarKeys.load(from: store).map(\.id), ["|", "end"])
    }

    func testEmptyListIsNotSaved() {
        KeyBarKeys.save([ExtraKey.with(id: "#")!], to: store)
        KeyBarKeys.save([], to: store)
        XCTAssertEqual(KeyBarKeys.load(from: store).map(\.id), ["#"])
    }

    func testCountIsCapped() {
        XCTAssertGreaterThan(ExtraKey.all.count, KeyBarKeys.maxCount)
        KeyBarKeys.save(ExtraKey.all, to: store)
        XCTAssertEqual(KeyBarKeys.load(from: store).map(\.id), ExtraKey.all.prefix(KeyBarKeys.maxCount).map(\.id))

        store.set(ExtraKey.all.map(\.id), forKey: KeyBarKeys.defaultsKey)
        XCTAssertEqual(KeyBarKeys.load(from: store).count, KeyBarKeys.maxCount)
    }

    func testIDsAreUnique() {
        let ids = ExtraKey.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testSymbolBytes() {
        let expected: [String: UInt8] = [
            "|": 0x7c, "~": 0x7e, "/": 0x2f, "-": 0x2d, "`": 0x60, "$": 0x24, "&": 0x26, "*": 0x2a,
            "\\": 0x5c, "_": 0x5f, ":": 0x3a, ";": 0x3b, "\"": 0x22, "'": 0x27, "<": 0x3c, ">": 0x3e,
            "{": 0x7b, "}": 0x7d, "[": 0x5b, "]": 0x5d, "(": 0x28, ")": 0x29, "=": 0x3d, "+": 0x2b,
            "#": 0x23, "%": 0x25, "@": 0x40, "!": 0x21, "?": 0x3f, "^": 0x5e,
        ]
        XCTAssertEqual(Set(ExtraKey.symbols.map(\.id)), Set(expected.keys))
        for key in ExtraKey.symbols {
            XCTAssertEqual(key.bytes(applicationCursor: false), [expected[key.id]!], key.id)
            XCTAssertEqual(key.bytes(applicationCursor: true), [expected[key.id]!], key.id)
        }
    }

    func testNamedKeyBytesMatchSwiftTerm() {
        let expected: [String: (normal: [UInt8], app: [UInt8])] = [
            "home": (EscapeSequences.moveHomeNormal, EscapeSequences.moveHomeApp),
            "end": (EscapeSequences.moveEndNormal, EscapeSequences.moveEndApp),
            "pageUp": (EscapeSequences.cmdPageUp, EscapeSequences.cmdPageUp),
            "pageDown": (EscapeSequences.cmdPageDown, EscapeSequences.cmdPageDown),
            "delete": (EscapeSequences.cmdDelKey, EscapeSequences.cmdDelKey),
        ]
        XCTAssertEqual(Set(ExtraKey.namedKeys.map(\.id)), Set(expected.keys))
        for key in ExtraKey.namedKeys {
            XCTAssertEqual(key.bytes(applicationCursor: false), expected[key.id]!.normal, key.id)
            XCTAssertEqual(key.bytes(applicationCursor: true), expected[key.id]!.app, key.id)
        }
        XCTAssertEqual(ExtraKey.with(id: "home")!.bytes(applicationCursor: false), [0x1b, 0x5b, 0x48])
        XCTAssertEqual(ExtraKey.with(id: "delete")!.bytes(applicationCursor: false), [0x1b, 0x5b, 0x33, 0x7e])
    }
}
