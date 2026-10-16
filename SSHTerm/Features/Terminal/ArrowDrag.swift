/// Turns drag travel on the key bar's arrow pad into arrow key presses.
///
/// Each `step` points of travel on the dominant axis is one key. Travel short of a step
/// carries to the next update, so a slow drag still moves. Kept free of UIKit so it can be tested.
struct ArrowDrag {
    enum Direction: Equatable {
        case up, down, left, right
    }

    static let defaultStep = 16.0

    let step: Double
    private(set) var remainderX = 0.0
    private(set) var remainderY = 0.0

    init(step: Double = ArrowDrag.defaultStep) {
        self.step = step
    }

    /// Adds one update's translation (y grows downward, as in UIKit) and returns the keys to send.
    mutating func update(dx: Double, dy: Double) -> [Direction] {
        remainderX += dx
        remainderY += dy
        let horizontal = abs(remainderX) > abs(remainderY)
        let travel = horizontal ? remainderX : remainderY
        let count = Int(abs(travel) / step)
        guard count > 0 else { return [] }

        let direction: Direction = horizontal
            ? (travel > 0 ? .right : .left)
            : (travel > 0 ? .down : .up)
        let used = Double(count) * step * (travel > 0 ? 1 : -1)
        // Drop the minor axis once a key fires, so a slightly diagonal drag does not drift sideways.
        if horizontal {
            remainderX -= used
            remainderY = 0
        } else {
            remainderY -= used
            remainderX = 0
        }
        return Array(repeating: direction, count: count)
    }

    mutating func reset() {
        remainderX = 0
        remainderY = 0
    }
}
