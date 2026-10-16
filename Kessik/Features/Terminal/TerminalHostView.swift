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
    let onCompose: () -> Void
    @AppStorage(SettingsKey.monoFont) private var fontFamily = MonoFont.defaultFamily
    @AppStorage(SettingsKey.terminalPalette) private var paletteID = TerminalPalette.defaultID
    @Environment(\.colorScheme) private var colorScheme

    /// The palette's colors for the app theme in use. Only Default changes with the theme.
    private var paletteColors: TerminalPalette.Colors {
        TerminalPalette.named(paletteID).colors(dark: colorScheme == .dark)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, watch: watch)
    }

    func makeUIView(context: Context) -> TerminalView {
        let view = AltScreenTerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        context.coordinator.apply(paletteColors, on: view)
        context.coordinator.setFont(on: view, family: fontFamily, size: fontSize)
        view.optionAsMetaKey = true
        let keyBar = KeyBar(terminal: view)
        keyBar.onCompose = onCompose
        view.inputAccessoryView = keyBar
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
        if context.coordinator.palette != paletteColors {
            context.coordinator.apply(paletteColors, on: view)
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
        /// The colors the view draws with now.
        private(set) var palette: TerminalPalette.Colors?

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

        /// Sets the text, background, cursor and ANSI colors. Only called when they change, because
        /// `installColors` also drops colors a program set with OSC 4.
        func apply(_ colors: TerminalPalette.Colors, on view: TerminalView) {
            let background = UIColor(hex: colors.background)
            // SwiftTerm paints the default background with the view's layer, and sets that layer
            // only once, at init. The layer goes first so reverse video saves the new color.
            view.layer.backgroundColor = background.cgColor
            view.nativeBackgroundColor = background
            view.nativeForegroundColor = UIColor(hex: colors.foreground)
            view.installColors(colors.ansi.compactMap(RGB8.init(hex:)).map {
                SwiftTerm.Color(red8: UInt16($0.red), green8: UInt16($0.green), blue8: UInt16($0.blue))
            })
            if colors.cursor == colors.foreground {
                // SwiftTerm's default cursor is the text color and swaps with it in reverse video.
                view.setCursorColor(source: view.getTerminal(), color: nil, textColor: nil)
            } else {
                view.caretColor = UIColor(hex: colors.cursor)
            }
            palette = colors
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

/// Keeps the alternate screen (tmux, vim, less) at one screen of lines.
///
/// SwiftTerm 1.19.0 raises the empty alternate screen's line limit when the view grows, but does
/// not lower it when the view shrinks. The terminal opens tall and the keyboard then shrinks it,
/// often before tmux starts. Each tmux scroll then adds a line instead of reusing one, and SwiftTerm
/// rests on the last line: the text drops by the space left under the last row, and the bottom of
/// an old row shows cut at the top.
final class AltScreenTerminalView: TerminalView {
    override func bufferActivated(source: Terminal) {
        if source.isCurrentBufferAlternate {
            // Sets the limit back to the row count. The cursor and scroll region stay as they are.
            source.buffer.changeHistorySize(nil)
        }
        super.bufferActivated(source: source)
    }
}

private extension UIColor {
    /// A palette hex string. The palette tests check that every one parses.
    convenience init(hex: String) {
        let rgb = RGB8(hex: hex) ?? RGB8(red: 0, green: 0, blue: 0)
        self.init(red: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255,
                  blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }
}
