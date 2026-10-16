import SwiftUI

/// Sheet shown on the Sessions tab after a Claude session is running on the Mac. The session started
/// with Remote Control on, so the user opens the Claude app, or opens the terminal here. Claude Code
/// still starts when Remote Control fails to connect, so the sheet does not say that it is on.
struct RemoteControlCard: View {
    var name: String
    var macName: String
    /// True when the session was already there, so nothing new started.
    var alreadyRunning: Bool
    var onOpenClaude: () -> Void
    var onOpenTerminal: () -> Void

    private static let codeURL = URL(string: "https://claude.ai/code")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(alreadyRunning ? "Already running" : "Session started", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.online)
            Text("\(Text(name).font(Theme.mono).bold()) runs on \(macName). Open the Claude app to control it from this phone, or open the terminal here. No app? Claude opens claude.ai/code in the browser.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onOpenClaude) {
                Label("Open Claude", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            Button(action: onOpenTerminal) {
                Label("Open terminal", systemImage: "terminal").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.textPrimary)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .background(Theme.background)
    }

    private var caption: String {
        var text = "If Claude Code asks to trust the folder or to confirm Remote Control, or shows an error, open the terminal and answer it. Remote Control needs a claude.ai login, not an API key."
        if alreadyRunning {
            text += " The Claude app lists this session only if it started with Remote Control."
        }
        return text
    }

    /// A universal link opens the Claude app when it is installed. Without the app the same address
    /// opens claude.ai/code in the browser.
    static func openClaude() {
        let url = codeURL
        Task {
            let opened = await UIApplication.shared.open(url, options: [.universalLinksOnly: true])
            if !opened { _ = await UIApplication.shared.open(url) }
        }
    }
}

#Preview {
    RemoteControlCard(name: "kessik", macName: "Studio", alreadyRunning: false, onOpenClaude: {}, onOpenTerminal: {})
        .preferredColorScheme(.dark)
}
