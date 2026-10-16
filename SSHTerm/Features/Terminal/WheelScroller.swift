import UIKit
import SwiftTerm

/// Turns a one-finger vertical swipe into scroll-wheel events while the program on screen reads
/// the mouse, such as tmux with `mouse on`. tmux keeps its history to itself, so SwiftTerm has
/// nothing to scroll there. In a plain shell this stays out of the way and SwiftTerm scrolls.
@MainActor
final class WheelScroller: NSObject, UIGestureRecognizerDelegate {
    /// tmux moves 5 lines for each wheel event, so 5 rows of finger travel keep the text under the finger.
    private static let rowsPerEvent: CGFloat = 5

    /// True while a wheel event goes out, so the terminal delegate can tell it from typed keys.
    private(set) var isSending = false
    private weak var view: TerminalView?
    private let onWheelUp: () -> Void
    /// Finger travel not yet sent as a wheel event.
    private var travel: CGFloat = 0
    /// Where the swipe started. tmux scrolls the pane under it.
    private var cell = (col: 0, row: 0)
    private var velocity: CGFloat = 0
    private var coast: CADisplayLink?

    init(view: TerminalView, onWheelUp: @escaping () -> Void) {
        self.view = view
        self.onWheelUp = onWheelUp
        super.init()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        // Two fingers are the text size pinch.
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    private var readsWheel: Bool {
        guard let mode = view?.getTerminal().mouseMode else { return false }
        return mode != .off && mode != .x10
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard readsWheel, let view, let pan = gesture as? UIPanGestureRecognizer else { return false }
        let speed = pan.velocity(in: view)
        return abs(speed.y) > abs(speed.x)
    }

    /// SwiftTerm's own gestures do nothing on a screen that reads the mouse, so both can run.
    func gestureRecognizer(_ gesture: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// A finger on the screen stops a coasting scroll, as in any iOS scroll view.
    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        stopCoasting()
        return true
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard let view else { return }
        switch gesture.state {
        case .began:
            // The first wheel event goes out after one row, not five, so a short swipe moves too.
            let direction: CGFloat = gesture.velocity(in: view).y >= 0 ? 1 : -1
            travel = direction * cellSize.height * (Self.rowsPerEvent - 1)
            let terminal = view.getTerminal()
            let point = gesture.location(in: view)
            cell = (col: min(max(Int(point.x / cellSize.width), 0), terminal.cols - 1),
                    row: min(max(Int(point.y / cellSize.height), 0), terminal.rows - 1))
        case .changed:
            move(gesture.translation(in: view).y)
            gesture.setTranslation(.zero, in: view)
        case .ended:
            velocity = gesture.velocity(in: view).y
            if abs(velocity) > 300 { startCoasting() }
        default:
            break
        }
    }

    private var cellSize: CGSize {
        guard let view else { return CGSize(width: 1, height: 1) }
        let terminal = view.getTerminal()
        return CGSize(width: view.bounds.width / CGFloat(max(terminal.cols, 1)),
                      height: view.bounds.height / CGFloat(max(terminal.rows, 1)))
    }

    /// A finger moving down pulls older lines into view, which is a wheel turn up.
    private func move(_ distance: CGFloat) {
        guard readsWheel else { return stopCoasting() }
        travel += distance
        let step = cellSize.height * Self.rowsPerEvent
        while abs(travel) >= step {
            let up = travel > 0
            sendWheel(up: up)
            travel -= up ? step : -step
        }
    }

    private func sendWheel(up: Bool) {
        guard let terminal = view?.getTerminal() else { return }
        let flags = terminal.encodeButton(button: up ? 4 : 5, release: false, shift: false, meta: false, control: false)
        isSending = true
        terminal.sendEvent(buttonFlags: flags, x: cell.col, y: cell.row)
        isSending = false
        if up { onWheelUp() }
    }

    // MARK: Coasting after a flick

    private func startCoasting() {
        stopCoasting()
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        coast = link
    }

    private func stopCoasting() {
        coast?.invalidate()
        coast = nil
    }

    /// Slows down at the rate of a normal UIScrollView.
    @objc private func step(_ link: CADisplayLink) {
        guard view != nil else { return stopCoasting() }
        let seconds = link.targetTimestamp - link.timestamp
        move(velocity * seconds)
        velocity *= pow(UIScrollView.DecelerationRate.normal.rawValue, seconds * 1000)
        if abs(velocity) < 60 { stopCoasting() }
    }
}
