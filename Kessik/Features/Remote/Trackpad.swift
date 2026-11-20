import SwiftUI
import UIKit

/// How finger movement on the pad becomes pointer movement on the Mac.
enum TrackpadMotion {
    /// Movement below this many points still counts as a tap.
    static let slop: CGFloat = 8
    /// A finger that stays down this long without moving starts a drag.
    static let holdTime: TimeInterval = 0.45
    /// A touch shorter than this, without movement, is a tap.
    static let tapTime: TimeInterval = 0.3
    static let scrollGain: CGFloat = 3

    /// A slow finger moves the pointer a little more than its own distance, for small targets.
    /// A fast finger moves it up to about five times as far, so one swipe crosses a TV.
    static func pointer(dx: CGFloat, dy: CGFloat) -> (dx: Double, dy: Double) {
        let speed = min(hypot(dx, dy), 30)
        let gain = 1.2 + speed * 0.12
        return (Double(dx * gain), Double(dy * gain))
    }
}

/// The touch surface of the Remote tab in Pointer mode. One finger moves the pointer and a tap
/// clicks. Two fingers scroll, and a tap with two fingers is a right click. Touch and hold, then
/// move, to drag.
struct Trackpad: UIViewRepresentable {
    var send: (RemoteCommand) -> Void
    /// Called for a click and for the start of a drag, so the view can give a haptic tap.
    var tapped: () -> Void

    func makeUIView(context: Context) -> TrackpadSurface {
        let view = TrackpadSurface()
        view.send = send
        view.tapped = tapped
        return view
    }

    func updateUIView(_ view: TrackpadSurface, context: Context) {
        view.send = send
        view.tapped = tapped
    }
}

final class TrackpadSurface: UIView {
    var send: (RemoteCommand) -> Void = { _ in }
    var tapped: () -> Void = {}

    private var active: Set<UITouch> = []
    private var began: TimeInterval = 0
    /// The most fingers down at once since the pad was last empty.
    private var most = 0
    private var travel: CGFloat = 0
    private var dragging = false
    private var hold: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if active.isEmpty {
            began = touches.first?.timestamp ?? 0
            most = 0
            travel = 0
            startHold()
        }
        active.formUnion(touches)
        most = max(most, active.count)
        if active.count > 1 { cancelHold() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        for touch in touches where active.contains(touch) {
            let now = touch.location(in: self)
            let before = touch.previousLocation(in: self)
            dx += now.x - before.x
            dy += now.y - before.y
        }
        guard !active.isEmpty, dx != 0 || dy != 0 else { return }
        // Two fingers can report in one call or in two. Dividing by the fingers down gives the
        // same total either way.
        dx /= CGFloat(active.count)
        dy /= CGFloat(active.count)
        travel += abs(dx) + abs(dy)
        if travel > TrackpadMotion.slop { cancelHold() }

        if active.count >= 2 {
            send(.scroll(dx: Double(dx * TrackpadMotion.scrollGain), dy: Double(dy * TrackpadMotion.scrollGain)))
        } else {
            let moved = TrackpadMotion.pointer(dx: dx, dy: dy)
            send(.move(dx: moved.dx, dy: moved.dy))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let ended = touches.first?.timestamp ?? 0
        active.subtract(touches)
        guard active.isEmpty else { return }
        cancelHold()
        if dragging {
            dragging = false
            send(.button(.left, .up))
        } else if travel < TrackpadMotion.slop, ended - began < TrackpadMotion.tapTime {
            tapped()
            send(.button(most >= 2 ? .right : .left, .click))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        active.subtract(touches)
        guard active.isEmpty else { return }
        cancelHold()
        if dragging {
            dragging = false
            send(.button(.left, .up))
        }
    }

    private func startHold() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.active.count == 1, self.travel < TrackpadMotion.slop, !self.dragging else { return }
            self.dragging = true
            self.tapped()
            self.send(.button(.left, .down))
        }
        hold = work
        DispatchQueue.main.asyncAfter(deadline: .now() + TrackpadMotion.holdTime, execute: work)
    }

    private func cancelHold() {
        hold?.cancel()
        hold = nil
    }
}

/// Takes the iOS keyboard without a text field on screen and sends each key to the Mac as it is typed.
struct KeyCatcher: UIViewRepresentable {
    @Binding var active: Bool
    var send: (RemoteCommand) -> Void

    func makeUIView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.send = send
        return view
    }

    func updateUIView(_ view: KeyCatcherView, context: Context) {
        view.send = send
        let wanted = active
        // A change of first responder during a view update is not allowed, so do it after.
        DispatchQueue.main.async {
            if wanted, !view.isFirstResponder {
                view.becomeFirstResponder()
            } else if !wanted, view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
    }
}

final class KeyCatcherView: UIView, UIKeyInput {
    var send: (RemoteCommand) -> Void = { _ in }

    // The Mac gets the keys as typed. A correction on the phone would never reach it.
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no

    override var canBecomeFirstResponder: Bool { true }

    /// Always true, so the delete key stays on.
    var hasText: Bool { true }

    func insertText(_ text: String) {
        if text == "\n" {
            send(.key(.enter))
        } else {
            send(.text(text))
        }
    }

    func deleteBackward() {
        send(.key(.delete))
    }
}
