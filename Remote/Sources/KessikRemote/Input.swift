import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import RemoteWire

/// Turns a command into pointer, keyboard and media key events. macOS drops these events until
/// the user allows Kessik Remote under Privacy & Security > Accessibility.
enum Input {
    private static let source = CGEventSource(stateID: .hidSystemState)
    private static var held: Set<RemoteButton> = []
    private static var lastDown: (time: TimeInterval, point: CGPoint, button: RemoteButton, count: Int64)?
    private static var scrollRest = CGPoint.zero

    static func perform(_ command: RemoteCommand) {
        switch command {
        case .auth: break
        case .move(let dx, let dy): move(dx: dx, dy: dy)
        case .button(let button, let press): self.press(button, press)
        case .scroll(let dx, let dy): scroll(dx: dx, dy: dy)
        case .key(let key): tap(keyCode(key))
        case .text(let text): type(text)
        case .action(let action): perform(action)
        }
    }

    static func releaseButtons() {
        for button in held { press(button, .up) }
    }

    // MARK: Pointer

    private static var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private static func move(dx: Double, dy: Double) {
        let from = location
        let to = clamp(CGPoint(x: from.x + dx, y: from.y + dy), from: from)
        // With a button held the same movement is a drag, or the app under the pointer never sees it.
        let type: CGEventType = held.contains(.left) ? .leftMouseDragged : held.contains(.right) ? .rightMouseDragged : .mouseMoved
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: to,
                            mouseButton: held.contains(.right) && !held.contains(.left) ? .right : .left)
        event?.setIntegerValueField(.mouseEventDeltaX, value: Int64((to.x - from.x).rounded()))
        event?.setIntegerValueField(.mouseEventDeltaY, value: Int64((to.y - from.y).rounded()))
        event?.post(tap: .cghidEventTap)
    }

    /// Keeps the pointer on a display. A point between or beyond the displays stays at the edge
    /// of the display it came from.
    private static func clamp(_ point: CGPoint, from: CGPoint) -> CGPoint {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success, count > 0 else { return point }
        let bounds = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
        if bounds.contains(where: { $0.contains(point) }) { return point }
        let home = bounds.first { $0.contains(from) } ?? CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: min(max(point.x, home.minX), home.maxX - 1),
                       y: min(max(point.y, home.minY), home.maxY - 1))
    }

    private static func press(_ button: RemoteButton, _ press: RemotePress) {
        switch press {
        case .click:
            self.press(button, .down)
            self.press(button, .up)
        case .down:
            let point = location
            let now = ProcessInfo.processInfo.systemUptime
            // A second press soon after the first, at the same place, is a double click.
            var count: Int64 = 1
            if let last = lastDown, last.button == button, now - last.time < NSEvent.doubleClickInterval,
               abs(last.point.x - point.x) < 6, abs(last.point.y - point.y) < 6 {
                count = min(last.count + 1, 3)
            }
            lastDown = (now, point, button, count)
            held.insert(button)
            post(button == .left ? .leftMouseDown : .rightMouseDown, button, at: point, count: count)
        case .up:
            guard held.remove(button) != nil else { return }
            post(button == .left ? .leftMouseUp : .rightMouseUp, button, at: location, count: lastDown?.count ?? 1)
        }
    }

    private static func post(_ type: CGEventType, _ button: RemoteButton, at point: CGPoint, count: Int64) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                            mouseButton: button == .left ? .left : .right)
        event?.setIntegerValueField(.mouseEventClickState, value: count)
        event?.post(tap: .cghidEventTap)
    }

    private static func scroll(dx: Double, dy: Double) {
        // Scroll events take whole pixels, so the fraction waits for the next one.
        scrollRest.x += dx
        scrollRest.y += dy
        let wholeX = scrollRest.x.rounded(.towardZero)
        let wholeY = scrollRest.y.rounded(.towardZero)
        guard wholeX != 0 || wholeY != 0 else { return }
        scrollRest.x -= wholeX
        scrollRest.y -= wholeY
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(wholeY), wheel2: Int32(wholeX), wheel3: 0)?.post(tap: .cghidEventTap)
    }

    // MARK: Keyboard

    private static func keyCode(_ key: RemoteKey) -> CGKeyCode {
        switch key {
        case .left: 123
        case .right: 124
        case .down: 125
        case .up: 126
        case .enter: 36
        case .escape: 53
        case .space: 49
        case .delete: 51
        case .tab: 48
        }
    }

    private static func tap(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Types text as Unicode, so it does not depend on the Mac's keyboard layout.
    private static func type(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if index > 0 { tap(keyCode(.enter)) }
            let units = Array(line.utf16)
            // One event carries up to 20 UTF-16 units.
            for start in stride(from: 0, to: units.count, by: 20) {
                let chunk = Array(units[start..<min(start + 20, units.count)])
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                    event?.flags = []
                    event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                    event?.post(tap: .cghidEventTap)
                }
            }
        }
    }

    // MARK: Actions

    private static func perform(_ action: RemoteAction) {
        switch action {
        // Command-[ is Back in Safari, Chrome, Finder and most media apps.
        case .back: tap(33, flags: .maskCommand)
        case .home:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        // Command-Space opens Spotlight, which starts an app by name.
        case .search: tap(49, flags: .maskCommand)
        case .power: togglePower()
        case .volumeUp: mediaKey(0)
        case .volumeDown: mediaKey(1)
        case .mute: mediaKey(7)
        case .playPause: mediaKey(16)
        case .next: mediaKey(17)
        case .previous: mediaKey(18)
        }
    }

    /// The keys on the top row of an Apple keyboard. They are system events, not key codes.
    private static func mediaKey(_ key: Int) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data = (key << 16) | ((down ? 0xA : 0xB) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Sleeps the display, or wakes it when it is asleep. The Mac itself stays on.
    private static func togglePower() {
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
            var assertion: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Kessik Remote" as CFString, kIOPMUserActiveLocal, &assertion)
        } else {
            let sleep = Process()
            sleep.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            sleep.arguments = ["displaysleepnow"]
            try? sleep.run()
        }
    }
}
