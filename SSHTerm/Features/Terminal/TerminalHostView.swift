import SwiftUI
import SwiftTerm
import UIKit

/// SwiftTerm's UIKit view, wired to an `SSHSession`.
struct TerminalHostView: UIViewRepresentable {
    /// Text sizes in points that pinch allows. The Settings stepper uses the same range.
    static let fontSizes: ClosedRange<CGFloat> = 9...24

    let session: SSHSession
    var fontSize: Double
    let watch: ScreenWatch
    @AppStorage(SettingsKey.monoFont) private var fontFamily = MonoFont.defaultFamily

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, watch: watch)
    }

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.nativeBackgroundColor = Theme.uiBackground
        view.nativeForegroundColor = Theme.uiTerminalText
        context.coordinator.setFont(on: view, family: fontFamily, size: fontSize)
        view.optionAsMetaKey = true
        view.inputAccessoryView = KeyBar(terminal: view)
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:))))
        // Taps, long press and text selection work as in a plain shell. Without this, SwiftTerm
        // sends them to tmux (mouse on) as clicks and drags. Only WheelScroller sends mouse events.
        view.allowMouseReporting = false
        context.coordinator.scroller = WheelScroller(view: view) { [weak watch] in watch?.didSwipeUp() }
        watch.terminal = view

        session.onOutput = { [weak view, weak watch] bytes in
            view?.feed(byteArray: bytes)
            watch?.screenChanged()
        }
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ view: TerminalView, context: Context) {
        if view.font.pointSize != fontSize || context.coordinator.family != fontFamily {
            context.coordinator.setFont(on: view, family: fontFamily, size: fontSize)
        }
    }

    static func dismantleUIView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.session.onOutput = nil
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let session: SSHSession
        let watch: ScreenWatch
        var scroller: WheelScroller?
        /// The family the view draws with now, as stored in Settings.
        private(set) var family = ""
        private var pinchStartSize: CGFloat = 0

        init(session: SSHSession, watch: ScreenWatch) {
            self.session = session
            self.watch = watch
        }

        /// Gives SwiftTerm all four faces, so bold and italic text use the same family.
        func setFont(on view: TerminalView, family: String, size: CGFloat) {
            let font = MonoFont.named(family)
            view.setFonts(normal: font.uiFont(size: size),
                          bold: font.uiFont(size: size, weight: .bold),
                          italic: font.uiFont(size: size, italic: true),
                          boldItalic: font.uiFont(size: size, weight: .bold, italic: true))
            self.family = family
        }

        /// Steps the text size in whole points, so the shell gets a resize only when the size
        /// changes, not on every frame of the pinch. Saves it for Settings and the next terminal.
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view as? TerminalView else { return }
            switch gesture.state {
            case .began:
                pinchStartSize = view.font.pointSize
            case .changed:
                let range = TerminalHostView.fontSizes
                let size = min(max((pinchStartSize * gesture.scale).rounded(), range.lowerBound), range.upperBound)
                guard size != view.font.pointSize else { return }
                setFont(on: view, family: family, size: size)
                UserDefaults.standard.set(Double(size), forKey: SettingsKey.terminalFontSize)
            default:
                break
            }
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            MainActor.assumeIsolated {
                // A typed key while tmux shows its history goes to the program, not to tmux.
                if scroller?.isSending != true { watch.leaveHistory() }
                session.send(Array(data))
            }
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            MainActor.assumeIsolated { session.resize(cols: newCols, rows: newRows) }
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            if let text = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = text
            }
        }

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func bell(source: TerminalView) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
