import XCTest
import SwiftTerm
@testable import Kessik

final class CursorShapeTests: XCTestCase {
    func testEveryShapeAndBlinkMapsToItsStyle() {
        let expected: [(CursorShape, Bool, CursorStyle)] = [
            (.block, true, .blinkBlock), (.block, false, .steadyBlock),
            (.bar, true, .blinkBar), (.bar, false, .steadyBar),
            (.underline, true, .blinkUnderline), (.underline, false, .steadyUnderline),
        ]
        for (shape, blink, style) in expected {
            XCTAssertEqual(shape.style(blink: blink), style, "\(shape) blink \(blink)")
            XCTAssertEqual(CursorShape.style(stored: shape.rawValue, blink: blink), style)
        }
        XCTAssertEqual(Set(expected.map { "\($0.2)" }).count, CursorStyle.allCases.count)
    }

    /// The default must look as the terminal did before the setting: SwiftTerm's own default.
    func testDefaultIsSwiftTermDefault() {
        XCTAssertEqual(CursorShape.block.style(blink: CursorShape.defaultBlink), TerminalOptions.default.cursorStyle)
    }

    func testUnknownStoredShapeFallsBackToBlock() {
        XCTAssertEqual(CursorShape.style(stored: "no-such-shape", blink: true), .blinkBlock)
        XCTAssertEqual(CursorShape.style(stored: "", blink: false), .steadyBlock)
    }
}
