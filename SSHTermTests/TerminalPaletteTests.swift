import XCTest
import SwiftTerm
import UIKit
@testable import SSHTerm

final class TerminalPaletteTests: XCTestCase {
    private var allColorSets: [(String, TerminalPalette.Colors)] {
        TerminalPalette.all.flatMap { palette in
            [(palette.name, palette.dark)] + (palette.light.map { [(palette.name + " light", $0)] } ?? [])
        }
    }

    func testEveryPaletteHasSixteenANSIColors() {
        for (name, colors) in allColorSets {
            XCTAssertEqual(colors.ansi.count, 16, name)
        }
    }

    func testEveryHexStringParses() {
        for (name, colors) in allColorSets {
            for hex in [colors.foreground, colors.background, colors.cursor] + colors.ansi {
                XCTAssertNotNil(RGB8(hex: hex), "\(name): \(hex)")
            }
        }
    }

    func testHexParsing() {
        XCTAssertEqual(RGB8(hex: "#0C0C0E"), RGB8(red: 12, green: 12, blue: 14))
        XCTAssertEqual(RGB8(hex: "fdf6e3"), RGB8(red: 0xFD, green: 0xF6, blue: 0xE3))
        XCTAssertNil(RGB8(hex: "#FFF"))
        XCTAssertNil(RGB8(hex: "#GGGGGG"))
        XCTAssertNil(RGB8(hex: "#+12345"))
        XCTAssertNil(RGB8(hex: ""))
    }

    func testIDsAreUnique() {
        let ids = TerminalPalette.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(TerminalPalette.all.first?.id, TerminalPalette.defaultID)
    }

    func testUnknownIDFallsBackToDefault() {
        XCTAssertEqual(TerminalPalette.named("no-such-palette"), .standard)
        XCTAssertEqual(TerminalPalette.named(""), .standard)
        XCTAssertEqual(TerminalPalette.named("gruvbox-dark").name, "Gruvbox Dark")
    }

    /// Default must look as the terminal did before palettes: the Theme colors, SwiftTerm's own
    /// ANSI colors, and a cursor in the text color.
    func testDefaultMatchesTheLookBeforePalettes() {
        for (isDark, style) in [(true, UIUserInterfaceStyle.dark), (false, .light)] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let colors = TerminalPalette.standard.colors(dark: isDark)
            assertClose(colors.background, Theme.uiBackground.resolvedColor(with: traits))
            assertClose(colors.foreground, Theme.uiTerminalText.resolvedColor(with: traits))
            XCTAssertEqual(colors.cursor, colors.foreground)
            let swiftTermDefault = SwiftTerm.Color.terminalAppColors.map { color in
                RGB8(red: UInt8(color.red / 257), green: UInt8(color.green / 257), blue: UInt8(color.blue / 257))
            }
            XCTAssertEqual(colors.ansi.compactMap(RGB8.init(hex:)), swiftTermDefault)
        }
    }

    func testFixedPalettesIgnoreTheAppTheme() {
        for palette in TerminalPalette.all where palette.id != TerminalPalette.defaultID {
            XCTAssertEqual(palette.colors(dark: true), palette.colors(dark: false), palette.name)
        }
    }

    @MainActor
    func testApplySetsTheViewColors() throws {
        let session = SSHSession(host: .unset)
        let coordinator = TerminalHostView.Coordinator(session: session, watch: ScreenWatch(session: session))
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let colors = TerminalPalette.named("solarized-light").dark

        coordinator.apply(colors, on: view)

        XCTAssertEqual(coordinator.palette, colors)
        let layer = try XCTUnwrap(view.layer.backgroundColor.map(UIColor.init(cgColor:)))
        assertClose(colors.background, layer)
        assertClose(colors.foreground, view.nativeForegroundColor)
        assertClose(colors.cursor, view.caretColor)
        let terminalBackground = view.getTerminal().backgroundColor
        XCTAssertEqual(terminalBackground, SwiftTerm.Color(red8: 0xFD, green8: 0xF6, blue8: 0xE3))
    }

    private func assertClose(_ hex: String, _ color: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let rgb = RGB8(hex: hex) else { return XCTFail("bad hex \(hex)", file: file, line: line) }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        // An 8-bit hex value is at most half a step from the color it rounds.
        let tolerance = 0.5 / 255 + 0.0001
        XCTAssertEqual(Double(rgb.red) / 255, Double(red), accuracy: tolerance, hex, file: file, line: line)
        XCTAssertEqual(Double(rgb.green) / 255, Double(green), accuracy: tolerance, hex, file: file, line: line)
        XCTAssertEqual(Double(rgb.blue) / 255, Double(blue), accuracy: tolerance, hex, file: file, line: line)
    }
}

/// Records the SwiftTerm behavior that `apply` works around.
final class SwiftTermBackgroundTests: XCTestCase {
    @MainActor
    func testNativeBackgroundDoesNotRepaintTheLayer() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.nativeBackgroundColor = .white
        let layer = view.layer.backgroundColor.map(UIColor.init(cgColor:))
        var white: CGFloat = 1, alpha: CGFloat = 0
        layer?.getWhite(&white, alpha: &alpha)
        XCTAssertEqual(white, 0, "SwiftTerm now repaints the layer; the layer line in apply can go")
    }
}
