import SwiftUI

/// The bytes that put `text` into the shell in one piece. With bracketed paste on (Claude Code
/// turns it on), the program reads it as one paste, so a new line in a dictated prompt does not send it.
enum PasteText {
    static func bytes(_ text: String, bracketed: Bool) -> [UInt8] {
        // A terminal sends Return as CR, so a pasted new line does too.
        let body = Array(text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r").utf8)
        guard bracketed else { return body }
        return [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e] + body + [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e]
    }
}

/// A text box for a long or dictated prompt. iOS dictation types into it word by word, and the
/// terminal gets the result in one paste when the user taps Insert or Send.
struct ComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    /// `send` true means Return follows the paste.
    let onDone: (_ text: String, _ send: Bool) -> Void

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(Theme.mono)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Theme.background)
                .focused($focused)
                .navigationTitle("Write a prompt")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .confirmationAction) {
                        Button("Insert") { finish(send: false) }
                            .disabled(text.isEmpty)
                        Button("Send") { finish(send: true) }
                            .bold()
                            .disabled(text.isEmpty)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear { focused = true }
    }

    private func finish(send: Bool) {
        onDone(text, send)
        dismiss()
    }
}
