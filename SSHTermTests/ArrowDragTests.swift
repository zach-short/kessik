import XCTest
@testable import SSHTerm

final class ArrowDragTests: XCTestCase {
    func testNoStepBelowThreshold() {
        var drag = ArrowDrag(step: 16)
        XCTAssertEqual(drag.update(dx: 15, dy: 0), [])
        XCTAssertEqual(drag.update(dx: 0, dy: -15.9), [])
    }

    func testLargeDeltaSendsSeveralSteps() {
        var drag = ArrowDrag(step: 16)
        XCTAssertEqual(drag.update(dx: 50, dy: 0), [.right, .right, .right])
        XCTAssertEqual(drag.remainderX, 2, accuracy: 0.0001)
    }

    func testLeftoverCarriesAcrossUpdates() {
        var drag = ArrowDrag(step: 16)
        XCTAssertEqual(drag.update(dx: 0, dy: 10), [])
        XCTAssertEqual(drag.update(dx: 0, dy: 10), [.down])
        XCTAssertEqual(drag.remainderY, 4, accuracy: 0.0001)
        XCTAssertEqual(drag.update(dx: 0, dy: 12), [.down])
    }

    func testDominantAxisWins() {
        var drag = ArrowDrag(step: 16)
        XCTAssertEqual(drag.update(dx: 10, dy: -20), [.up])
        XCTAssertEqual(drag.remainderX, 0)

        var sideways = ArrowDrag(step: 16)
        XCTAssertEqual(sideways.update(dx: -40, dy: 20), [.left, .left])
        XCTAssertEqual(sideways.remainderY, 0)
    }

    func testDirectionReversal() {
        var drag = ArrowDrag(step: 16)
        XCTAssertEqual(drag.update(dx: 40, dy: 0), [.right, .right])
        // The 8 points left over are paid back before the first left key.
        XCTAssertEqual(drag.update(dx: -20, dy: 0), [])
        XCTAssertEqual(drag.update(dx: -10, dy: 0), [.left])
        XCTAssertEqual(drag.remainderX, -6, accuracy: 0.0001)
    }

    func testResetClearsLeftover() {
        var drag = ArrowDrag(step: 16)
        XCTAssertEqual(drag.update(dx: 12, dy: 6), [])
        drag.reset()
        XCTAssertEqual(drag.remainderX, 0)
        XCTAssertEqual(drag.remainderY, 0)
        XCTAssertEqual(drag.update(dx: 12, dy: 0), [])
    }
}
