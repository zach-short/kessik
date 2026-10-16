import SwiftUI

/// Sheet shown over the terminal of a new Claude session. The session starts with Remote Control on,
/// so the user picks the Claude app or stays in the terminal. Either pick closes the sheet. Claude Code
/// still starts when Remote Control fails to connect, so the sheet does not say that it is on.
struct RemoteControlCard: View {
    var name: String
    var onDismiss: () -> Void

    private static let codeURL = URL(string: "https://claude.ai/code")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Control it from your phone", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Open the Claude app to control \(Text(name).font(Theme.mono).bold()) from this phone. No app? Claude opens claude.ai/code in the browser.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openClaude) {
                Label("Open Claude", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Stay in the terminal", action: onDismiss)
                .frame(maxWidth: .infinity)
            Text("If Claude Code asks to confirm Remote Control or shows an error, answer it in the terminal. Remote Control needs a claude.ai login, not an API key.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .background(Theme.background)
    }

    /// A universal link opens the Claude app when it is installed. Without the app the same address
    /// opens claude.ai/code in the browser.
    private func openClaude() {
        let url = Self.codeURL
        Task {
            let opened = await UIApplication.shared.open(url, options: [.universalLinksOnly: true])
            if !opened { _ = await UIApplication.shared.open(url) }
        }
        onDismiss()
    }
}

#Preview {
    RemoteControlCard(name: "sshterm") {}
        .preferredColorScheme(.dark)
}
