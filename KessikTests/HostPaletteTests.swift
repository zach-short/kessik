import XCTest
@testable import Kessik

final class HostPaletteTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "HostPaletteTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func mac(palette: String? = nil) -> Host {
        Host(name: "Mac", hostname: "mac.tailnet.ts.net", username: "user", paletteID: palette)
    }

    /// A Mac as builds before per-Mac colors saved it, with no `paletteID` key.
    func testOldHostJSONDecodesWithoutPalette() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Mac","hostname":"mac.local",
         "port":22,"username":"user","status":"unknown"}
        """
        let host = try JSONDecoder().decode(Host.self, from: Data(json.utf8))
        XCTAssertNil(host.paletteID)
        XCTAssertEqual(host.hostname, "mac.local")
        XCTAssertEqual(host.id.uuidString, "6F9619FF-8B86-D011-B42D-00C04FC964FF")
    }

    func testOldMacListDecodesWithoutPalette() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Mac","hostname":"mac.local",
          "port":22,"username":"user","status":"unknown"}]
        """
        defaults.set(Data(json.utf8), forKey: SavedMacs.listKey)
        let list = SavedMacs(defaults: defaults).load()
        XCTAssertEqual(list.macs.count, 1)
        XCTAssertNil(list.macs[0].paletteID)
    }

    func testPaletteRoundTripsThroughJSON() throws {
        let host = mac(palette: "gruvbox-dark")
        let decoded = try JSONDecoder().decode(Host.self, from: JSONEncoder().encode(host))
        XCTAssertEqual(decoded.paletteID, "gruvbox-dark")
    }

    func testMacWithoutPaletteUsesGlobal() {
        let palette = TerminalPalette.resolve(host: mac(), global: "tokyo-night", available: TerminalPalette.all)
        XCTAssertEqual(palette.id, "tokyo-night")
    }

    func testMacPaletteWinsOverGlobal() {
        let palette = TerminalPalette.resolve(host: mac(palette: "solarized-light"), global: "tokyo-night",
                                              available: TerminalPalette.all)
        XCTAssertEqual(palette.id, "solarized-light")
    }

    func testNoHostUsesGlobal() {
        let palette = TerminalPalette.resolve(host: nil, global: "gruvbox-dark", available: TerminalPalette.all)
        XCTAssertEqual(palette.id, "gruvbox-dark")
    }

    func testUnknownMacPaletteFallsBackToGlobal() {
        let palette = TerminalPalette.resolve(host: mac(palette: "custom-gone"), global: "gruvbox-dark",
                                              available: TerminalPalette.all)
        XCTAssertEqual(palette.id, "gruvbox-dark")
    }

    func testUnknownMacAndGlobalPalettesFallBackToDefault() {
        let palette = TerminalPalette.resolve(host: mac(palette: "custom-gone"), global: "custom-also-gone",
                                              available: TerminalPalette.all)
        XCTAssertEqual(palette, .standard)
    }

    func testDeletedImportedPaletteFallsBackToGlobal() throws {
        let palettes = CustomPalettes(defaults: defaults)
        let imported = try palettes.add(name: "Mine", data: Self.preset)
        let host = mac(palette: imported.id)

        let before = TerminalPalette.resolve(host: host, global: "tokyo-night",
                                             available: TerminalPalette.available(defaults: defaults))
        XCTAssertEqual(before.id, imported.id)

        palettes.delete(id: imported.id)
        let after = TerminalPalette.resolve(host: host, global: "tokyo-night",
                                            available: TerminalPalette.available(defaults: defaults))
        XCTAssertEqual(after.id, "tokyo-night")
    }

    func testBuiltInsComeFirstInAvailable() {
        let available = TerminalPalette.available(defaults: defaults)
        XCTAssertEqual(Array(available.prefix(TerminalPalette.all.count)), TerminalPalette.all)
    }

    /// The smallest preset `CustomPalettes.parse` accepts: Ansi 0 to 15, Background and Foreground.
    private static var preset: Data {
        let gray: [String: Any] = ["Red Component": 0.5, "Green Component": 0.5, "Blue Component": 0.5]
        var entries: [String: Any] = ["Background Color": gray, "Foreground Color": gray]
        for n in 0..<16 { entries["Ansi \(n) Color"] = gray }
        return try! PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
    }
}
