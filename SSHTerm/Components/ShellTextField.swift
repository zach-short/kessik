import SwiftUI
import UIKit

/// A multi-line field for text the shell reads. The system field turns `--` into a dash and `'`
/// into a curly quote, which breaks commands, and SwiftUI has no switch for that.
struct ShellTextField: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(prompt)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            PlainTextView(text: $text, label: prompt)
        }
    }
}

private struct PlainTextView: UIViewRepresentable {
    @Binding var text: String
    var label: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.text = text
        view.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.textColor = Theme.uiTextPrimary
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.smartInsertDeleteType = .no
        view.accessibilityLabel = label
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        // While typing, the view holds the newest text. An update can carry an older value, and
        // writing it back drops keys and moves the cursor.
        if !view.isFirstResponder, view.text != text { view.text = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}
