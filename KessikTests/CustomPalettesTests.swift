import XCTest
@testable import Kessik

final class CustomPalettesTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: CustomPalettes!

    override func setUp() {
        super.setUp()
        suiteName = "CustomPalettesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = CustomPalettes(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: Fixture

    /// A small iTerm2 preset in the form iTerm2 exports: Ansi 0 to 15, Background, Foreground,
    /// Cursor and Selection, each a dict of Red, Green and Blue components. Ansi n is (n/15, 0, 1).
    private static let entries: [(String, String)] = (0..<16).map { n in
        ("Ansi \(n) Color", colorDict(red: "\(Double(n) / 15)", green: "0", blue: "1"))
    } + [
        ("Background Color", colorDict(red: "0.2", green: "0.4", blue: "0.6")),
        ("Foreground Color", colorDict(red: "0.8", green: "0.6", blue: "1")),
        ("Cursor Color", colorDict(red: "1", green: "0.5", blue: "0")),
        ("Selection Color", colorDict(red: "0.25", green: "0.25", blue: "0.25")),
    ]

    private static func colorDict(red: String, green: String, blue: String) -> String {
        """
        <dict>
        \t<key>Alpha Component</key><real>1</real>
        \t<key>Blue Component</key><real>\(blue)</real>
        \t<key>Color Space</key><string>sRGB</string>
        \t<key>Green Component</key><real>\(green)</real>
        \t<key>Red Component</key><real>\(red)</real>
        </dict>
        """
    }

    /// The fixture as plist text, with one entry left out or replaced.
    private static func fixture(omitting omitted: String? = nil, replacing replaced: [String: String] = [:]) -> Data {
        let body = entries
            .filter { $0.0 != omitted }
            .map { key, value in "<key>\(key)</key>\n\(replaced[key] ?? value)" }
            .joined(separator: "\n")
        let text = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(body)
        </dict>
        </plist>
        """
        return Data(text.utf8)
    }

    // MARK: Import

    func testValidThemeImports() throws {
        let colors = try CustomPalettes.parse(Self.fixture())
        XCTAssertEqual(colors.background, "#336699")
        XCTAssertEqual(colors.foreground, "#CC99FF")
        XCTAssertEqual(colors.cursor, "#FF8000")
        XCTAssertEqual(colors.ansi.count, 16)
        XCTAssertEqual(colors.ansi.first, "#0000FF")
        XCTAssertEqual(colors.ansi.last, "#FF00FF")
        XCTAssertEqual(colors.ansi[3], "#3300FF")

        let palette = try store.add(name: "  Sample  ", data: Self.fixture())
        XCTAssertEqual(palette.name, "Sample")
        XCTAssertTrue(palette.id.hasPrefix(CustomPalettes.idPrefix))
        XCTAssertEqual(palette.dark, colors)
        XCTAssertNil(palette.light)
        XCTAssertEqual(store.palettes, [palette])
        XCTAssertEqual(TerminalPalette.named(palette.id, defaults: defaults), palette)
    }

    func testBinaryPlistImports() throws {
        let plist = try PropertyListSerialization.propertyList(from: Self.fixture(), format: nil)
        let binary = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        XCTAssertEqual(try CustomPalettes.parse(binary), try CustomPalettes.parse(Self.fixture()))
    }

    func testMissingCursorUsesTheTextColor() throws {
        let colors = try CustomPalettes.parse(Self.fixture(omitting: "Cursor Color"))
        XCTAssertEqual(colors.cursor, colors.foreground)
    }

    // MARK: Rejection

    func testMalformedInputIsRejected() {
        let inputs: [Data] = [
            Data(),
            Data("not a plist".utf8),
            Data([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30, 0xFF, 0xFF]),
            Data(String(decoding: Self.fixture(), as: UTF8.self).dropLast(20).utf8),
            Data(#"<?xml version="1.0"?><plist version="1.0"><array><string>x</string></array></plist>"#.utf8),
            Data(#"<?xml version="1.0"?><plist version="1.0"><string>Ansi 0 Color</string></plist>"#.utf8),
        ]
        for data in inputs {
            XCTAssertThrowsError(try CustomPalettes.parse(data)) { error in
                XCTAssertEqual(error as? CustomPalettes.ImportError, .notAPlist)
            }
        }
    }

    func testEachRequiredColorIsRequired() {
        let required = (0..<16).map { "Ansi \($0) Color" } + ["Background Color", "Foreground Color"]
        for key in required {
            XCTAssertThrowsError(try CustomPalettes.parse(Self.fixture(omitting: key)), key) { error in
                XCTAssertEqual(error as? CustomPalettes.ImportError, .missingColor(key))
            }
        }
    }

    func testBadComponentsAreRejected() {
        let bad = [
            Self.colorDict(red: "1.5", green: "0", blue: "0"),
            Self.colorDict(red: "0", green: "-0.1", blue: "0"),
            Self.colorDict(red: "0", green: "0", blue: "nan"),
            Self.colorDict(red: "0", green: "0", blue: "+infinity"),
            "<dict><key>Red Component</key><string>0.5</string><key>Green Component</key><real>0</real><key>Blue Component</key><real>0</real></dict>",
            "<dict><key>Red Component</key><true/><key>Green Component</key><real>0</real><key>Blue Component</key><real>0</real></dict>",
            "<dict><key>Red Component</key><real>0</real><key>Green Component</key><real>0</real></dict>",
            "<string>#FF0000</string>",
            "<array><real>1</real><real>0</real><real>0</real></array>",
        ]
        for key in ["Ansi 7 Color", "Background Color", "Cursor Color"] {
            for value in bad {
                XCTAssertThrowsError(try CustomPalettes.parse(Self.fixture(replacing: [key: value])), value) { error in
                    XCTAssertEqual(error as? CustomPalettes.ImportError, .badColor(key))
                }
            }
        }
    }

    func testComponentBoundsAreAccepted() throws {
        let colors = try CustomPalettes.parse(Self.fixture(replacing: [
            "Background Color": Self.colorDict(red: "0", green: "1", blue: "0"),
            "Foreground Color": "<dict><key>Red Component</key><integer>1</integer><key>Green Component</key><integer>0</integer><key>Blue Component</key><integer>1</integer></dict>",
        ]))
        XCTAssertEqual(colors.background, "#00FF00")
        XCTAssertEqual(colors.foreground, "#FF00FF")
    }

    func testOversizedDataIsRejected() {
        let padding = String(repeating: " ", count: CustomPalettes.maxFileSize)
        let data = Data((String(decoding: Self.fixture(), as: UTF8.self) + padding).utf8)
        XCTAssertThrowsError(try CustomPalettes.parse(data)) { error in
            XCTAssertEqual(error as? CustomPalettes.ImportError, .tooLarge)
        }
        XCTAssertTrue(store.palettes.isEmpty)
    }

    func testNameRules() throws {
        for name in ["", "   ", "\n", "Bad\u{0}Name", "Two\nLines"] {
            XCTAssertThrowsError(try store.add(name: name, data: Self.fixture()), name) { error in
                XCTAssertEqual(error as? CustomPalettes.ImportError, .badName)
            }
        }
        let longest = String(repeating: "é", count: CustomPalettes.maxNameLength)
        XCTAssertEqual(try store.add(name: longest, data: Self.fixture()).name, longest)
        XCTAssertThrowsError(try store.add(name: longest + "x", data: Self.fixture())) { error in
            XCTAssertEqual(error as? CustomPalettes.ImportError, .nameTooLong)
        }
        XCTAssertEqual(store.palettes.count, 1)
    }

    func testRejectedImportSavesNothing() {
        XCTAssertThrowsError(try store.add(name: "Broken", data: Self.fixture(omitting: "Ansi 15 Color")))
        XCTAssertTrue(store.palettes.isEmpty)
        XCTAssertNil(defaults.data(forKey: CustomPalettes.key))
    }

    func testThemeCountIsCapped() throws {
        for n in 0..<CustomPalettes.maxCount {
            try store.add(name: "Theme \(n)", data: Self.fixture())
        }
        XCTAssertThrowsError(try store.add(name: "One more", data: Self.fixture())) { error in
            XCTAssertEqual(error as? CustomPalettes.ImportError, .tooMany)
        }
        XCTAssertEqual(store.palettes.count, CustomPalettes.maxCount)
        XCTAssertEqual(Set(store.palettes.map(\.id)).count, CustomPalettes.maxCount)

        store.delete(id: store.palettes[0].id)
        XCTAssertNoThrow(try store.add(name: "One more", data: Self.fixture()))
    }

    // MARK: Delete and fallback

    func testDeleteRemovesThePalette() throws {
        let first = try store.add(name: "First", data: Self.fixture())
        let second = try store.add(name: "Second", data: Self.fixture())
        store.delete(id: first.id)
        XCTAssertEqual(store.palettes, [second])
        store.delete(id: "custom-no-such-id")
        XCTAssertEqual(store.palettes, [second])
    }

    func testDeletingTheSelectedPaletteSelectsDefault() throws {
        let palette = try store.add(name: "Mine", data: Self.fixture())
        defaults.set(palette.id, forKey: SettingsKey.terminalPalette)
        store.delete(id: palette.id)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.terminalPalette), TerminalPalette.defaultID)
    }

    func testDeletingAnotherPaletteKeepsTheSelection() throws {
        let palette = try store.add(name: "Mine", data: Self.fixture())
        defaults.set("gruvbox-dark", forKey: SettingsKey.terminalPalette)
        store.delete(id: palette.id)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.terminalPalette), "gruvbox-dark")
    }

    /// A selection saved before its palette went away, for example by a delete on an older build.
    func testMissingImportedPaletteFallsBackToDefault() throws {
        let palette = try store.add(name: "Gone", data: Self.fixture())
        defaults.removeObject(forKey: CustomPalettes.key)
        XCTAssertEqual(TerminalPalette.named(palette.id, defaults: defaults), .standard)
        XCTAssertEqual(TerminalPalette.named("custom-", defaults: defaults), .standard)
    }

    func testCorruptStoredDataIsIgnored() throws {
        defaults.set(Data("garbage".utf8), forKey: CustomPalettes.key)
        XCTAssertTrue(store.palettes.isEmpty)
        defaults.set("not data", forKey: CustomPalettes.key)
        XCTAssertTrue(store.palettes.isEmpty)

        let good = try store.add(name: "Good", data: Self.fixture())
        var records = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: CustomPalettes.key))) as? [[String: Any]])
        var badHex = records[0]
        badHex["id"] = "custom-bad-hex"
        badHex["background"] = "#ZZZZZZ"
        var shortANSI = records[0]
        shortANSI["id"] = "custom-short"
        shortANSI["ansi"] = ["#000000"]
        var builtInID = records[0]
        builtInID["id"] = "gruvbox-dark"
        records += [badHex, shortANSI, builtInID]
        defaults.set(try JSONSerialization.data(withJSONObject: records), forKey: CustomPalettes.key)

        XCTAssertEqual(store.palettes, [good])
    }

    // MARK: Built-ins

    func testBuiltInsAreUnchanged() throws {
        let builtInIDs = ["default", "solarized-dark", "solarized-light", "gruvbox-dark", "tokyo-night", "one-half-light"]
        XCTAssertEqual(TerminalPalette.all.map(\.id), builtInIDs)

        try store.add(name: "Gruvbox Dark", data: Self.fixture())
        defaults.set("solarized-dark", forKey: SettingsKey.terminalPalette)
        XCTAssertEqual(TerminalPalette.all.map(\.id), builtInIDs)
        for id in builtInIDs {
            XCTAssertEqual(TerminalPalette.named(id, defaults: defaults), TerminalPalette.named(id))
            XCTAssertEqual(TerminalPalette.named(id, defaults: defaults).id, id)
        }

        store.delete(id: store.palettes[0].id)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.terminalPalette), "solarized-dark")
        XCTAssertEqual(TerminalPalette.named("solarized-dark", defaults: defaults).name, "Solarized Dark")
    }
}
