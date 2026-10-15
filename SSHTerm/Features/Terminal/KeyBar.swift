import SwiftTerm
import UIKit

/// The row above the keyboard: keys a phone keyboard lacks, plus copy and paste.
final class KeyBar: UIInputView, UIInputViewAudioFeedback {
    private weak var terminal: TerminalView?
    private let stack = UIStackView()
    private var ctrlButton: UIButton!
    private var repeatTimer: Timer?
    private let tapHaptic = UIImpactFeedbackGenerator(style: .light)
    private let copyHaptic = UINotificationFeedbackGenerator()

    var enableInputClicksWhenVisible: Bool { true }

    /// Read on every tap, so the Settings toggle applies to a terminal that is already open.
    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.hapticsEnabled) as? Bool ?? true
    }

    init(terminal: TerminalView) {
        self.terminal = terminal
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        backgroundColor = UIColor(Theme.background)
        build()
        NotificationCenter.default.addObserver(
            self, selector: #selector(ctrlReset),
            name: .terminalViewControlModifierReset, object: terminal
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44) }

    // MARK: Layout

    private func build() {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let fixed = UIStackView()
        fixed.axis = .horizontal
        fixed.spacing = 6
        fixed.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fixed)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: fixed.leadingAnchor, constant: -6),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -6),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -12),

            fixed.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            fixed.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            fixed.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        stack.addArrangedSubview(key("esc") { $0.send([0x1b]) })
        ctrlButton = key("ctrl") { [weak self] t in
            t.controlModifier.toggle()
            self?.ctrlButton.isSelected = t.controlModifier
        }
        stack.addArrangedSubview(ctrlButton)
        stack.addArrangedSubview(key(icon: "arrow.right.to.line") { $0.send([0x09]) })
        stack.addArrangedSubview(arrow("arrow.left", app: EscapeSequences.moveLeftApp, normal: EscapeSequences.moveLeftNormal))
        stack.addArrangedSubview(arrow("arrow.up", app: EscapeSequences.moveUpApp, normal: EscapeSequences.moveUpNormal))
        stack.addArrangedSubview(arrow("arrow.down", app: EscapeSequences.moveDownApp, normal: EscapeSequences.moveDownNormal))
        stack.addArrangedSubview(arrow("arrow.right", app: EscapeSequences.moveRightApp, normal: EscapeSequences.moveRightNormal))
        for symbol in ["|", "~", "/", "-", "`", "$", "&", "*", "\\"] {
            stack.addArrangedSubview(key(symbol) { $0.send(txt: symbol) })
        }

        fixed.addArrangedSubview(key(icon: "doc.on.doc", label: "Copy", tapFeedback: false) { [weak self] t in self?.copy(from: t) })
        fixed.addArrangedSubview(key(icon: "doc.on.clipboard", label: "Paste") { $0.paste(nil) })
        fixed.addArrangedSubview(key(icon: "keyboard.chevron.compact.down", label: "Hide keyboard") { _ = $0.resignFirstResponder() })
    }

    // MARK: Buttons

    /// `tapFeedback: false` is for a key whose action plays its own haptic.
    private func key(_ title: String? = nil, icon: String? = nil, label: String? = nil,
                     tapFeedback: Bool = true, action: ((TerminalView) -> Void)? = nil) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
        config.baseForegroundColor = UIColor(Theme.textPrimary)
        if let title {
            var attributes = AttributeContainer()
            attributes.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)
            config.attributedTitle = AttributedString(title, attributes: attributes)
        }
        if let icon {
            config.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        }

        let button = UIButton(configuration: config)
        button.configurationUpdateHandler = { button in
            var config = button.configuration
            config?.baseBackgroundColor = button.isSelected || button.isHighlighted
                ? UIColor(Theme.accent).withAlphaComponent(0.35)
                : UIColor(Theme.surfaceRaised)
            button.configuration = config
        }
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        button.accessibilityLabel = label ?? title
        if let action {
            // Wake the Taptic Engine on touch down, so the haptic on touch up has no lag.
            button.addAction(UIAction { [weak self] _ in
                guard let self, self.hapticsEnabled else { return }
                if tapFeedback { self.tapHaptic.prepare() } else { self.copyHaptic.prepare() }
            }, for: .touchDown)
            button.addAction(UIAction { [weak self] _ in
                guard let self, let terminal = self.terminal else { return }
                if tapFeedback { self.keyFeedback() }
                action(terminal)
            }, for: .touchUpInside)
        }
        return button
    }

    /// The input click (it follows the system Keyboard Clicks setting) and the haptic (it follows ours).
    private func keyFeedback() {
        UIDevice.current.playInputClick()
        if hapticsEnabled { tapHaptic.impactOccurred() }
    }

    /// Arrow keys repeat while held, and follow the shell's cursor-key mode.
    private func arrow(_ icon: String, app: [UInt8], normal: [UInt8]) -> UIButton {
        let button = key(icon: icon, label: icon.replacingOccurrences(of: ".", with: " "))
        let fire: () -> Void = { [weak self] in
            guard let terminal = self?.terminal else { return }
            terminal.send(terminal.getTerminal().applicationCursor ? app : normal)
        }
        button.addAction(UIAction { [weak self] _ in
            self?.keyFeedback()
            fire()
            self?.repeatTimer?.invalidate()
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in fire() }
            }
        }, for: .touchDown)
        button.addAction(UIAction { [weak self] _ in
            self?.repeatTimer?.invalidate()
            self?.repeatTimer = nil
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return button
    }

    // MARK: Actions

    /// Copies the selection. With no selection, copies the visible screen.
    private func copy(from terminal: TerminalView) {
        if terminal.selection.active {
            terminal.copy(nil)
        } else {
            let t = terminal.getTerminal()
            let top = t.buffer.yDisp
            UIPasteboard.general.string = t.getText(
                start: Position(col: 0, row: top),
                end: Position(col: t.cols - 1, row: top + t.rows - 1)
            )
        }
        UIDevice.current.playInputClick()
        if hapticsEnabled { copyHaptic.notificationOccurred(.success) }
    }

    @objc private func ctrlReset() {
        ctrlButton.isSelected = false
    }
}
