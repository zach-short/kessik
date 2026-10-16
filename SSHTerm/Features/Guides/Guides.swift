import SwiftUI

/// A how-to page: numbered steps, then fixes for the errors the app shows. Text is Markdown, so
/// `code` and *emphasis* render.
struct Guide: Identifiable, Hashable {
    let id: String
    var title: String
    var symbol: String
    var summary: String
    var steps: [Step]
    var fixesTitle = "If it does not work"
    var fixes: [Fix] = []

    struct Step: Hashable {
        var title: String
        var text: String
        /// Shown in a box with a copy button, for the user to run on the Mac.
        var command: String?
        /// Adds a button that goes to this tab.
        var opens: AppTab?
        /// Shown in place of the step number, for a guide that is not a sequence.
        var symbol: String?
    }

    struct Fix: Hashable {
        var problem: String
        var fix: String
    }
}

extension Guide {
    static let all: [Guide] = [.connectMac, .sshKey, .claudeSetup, .terminal]

    static let connectMac = Guide(
        id: "connect-mac",
        title: "Connect to a Mac",
        symbol: "laptopcomputer",
        summary: "Set up the Mac once. Then this phone can open Claude Code on it from any network.",
        steps: [
            Step(title: "Turn on Remote Login",
                 text: "On the Mac, open System Settings > General > Sharing. Turn on Remote Login. The Mac then accepts SSH logins."),
            Step(title: "Put both on Tailscale",
                 text: "Install Tailscale on the Mac and on this phone. Sign in to the same account on both. The phone can then reach the Mac away from home."),
            Step(title: "Find the hostname",
                 text: "Open Tailscale on this phone and find the Mac in the device list. Use its name, such as `my-mac.tailnet-name.ts.net`, or its 100.x address."),
            Step(title: "Find the username",
                 text: "On the Mac, open Terminal and run this command. It prints the short username.",
                 command: "whoami"),
            Step(title: "Save the Mac in Settings",
                 text: "Enter the hostname and the username. Leave the port empty to use 22. Tap Save.",
                 opens: .settings),
            Step(title: "Connect",
                 text: "In the Sessions tab, type the Mac's login password and tap Connect. The first connection saves the Mac's host key. If that key changes later, the app stops the connection.",
                 opens: .sessions),
        ],
        fixesTitle: "If it does not connect",
        fixes: [
            Fix(problem: "\"Refused the connection\"",
                fix: "Remote Login is off. Turn it on in System Settings > General > Sharing on the Mac."),
            Fix(problem: "\"Was not found\" or \"did not answer\"",
                fix: "Check that Tailscale is on for this phone and for the Mac. Check that the Mac is awake."),
            Fix(problem: "\"The Mac refused the login\"",
                fix: "Check the username, and use the password you type to log in to the Mac."),
        ]
    )

    static let sshKey = Guide(
        id: "ssh-key",
        title: "Log in without a password",
        symbol: "key",
        summary: "Add this phone's SSH key to the Mac. Then Connect works with an empty password.",
        steps: [
            Step(title: "Make a key",
                 text: "In Settings > SSH key, tap Generate SSH key. The private key stays in this phone's Keychain.",
                 opens: .settings),
            Step(title: "Connect with the password",
                 text: "Connect once in the Sessions tab with the Mac's password.",
                 opens: .sessions),
            Step(title: "Add the key to the Mac",
                 text: "In Settings > SSH key, tap *Add to* and the Mac's hostname. The app adds the public key to `~/.ssh/authorized_keys` on the Mac.",
                 opens: .settings),
            Step(title: "Connect with no password",
                 text: "Leave the password empty and tap Connect. The app tries the key first, then a saved password."),
        ],
        fixes: [
            Fix(problem: "The Mac accepts keys only",
                fix: "Copy or share the public key in Settings. On the Mac, add it as a new line in `~/.ssh/authorized_keys`."),
            Fix(problem: "The key stopped working",
                fix: "*New key* replaces the old key. Add the new key to the Mac again."),
        ]
    )

    static let claudeSetup = Guide(
        id: "claude-setup",
        title: "Set up Claude Code on the Mac",
        symbol: "sparkles",
        summary: "The app opens Claude Code in tmux on the Mac. A tmux session keeps running when this phone disconnects.",
        steps: [
            Step(title: "Install tmux",
                 text: "On the Mac, install tmux with Homebrew.",
                 command: "brew install tmux"),
            Step(title: "Install Claude Code",
                 text: "Run the installer. Then run `claude` once in Terminal to sign in.",
                 command: "curl -fsSL https://claude.ai/install.sh | bash"),
            Step(title: "Put repos in ~/Projects",
                 text: "The folder list shows the folders in `~/Projects` on the Mac, newest first. For another folder, type its path, such as `~/code/app`."),
            Step(title: "Start a session",
                 text: "In the Sessions tab, tap New Claude session and pick a folder. The tmux session gets the folder's name.",
                 opens: .sessions),
            Step(title: "Come back to it",
                 text: "Close the terminal at any time. Claude keeps running on the Mac. Tap the session in the Sessions tab to attach again. Touch and hold it to kill it."),
        ],
        fixes: [
            Fix(problem: "\"tmux is not installed\"",
                fix: "The app looks for tmux in `/opt/homebrew/bin` and `/usr/local/bin`. Install it with Homebrew, then pull down on the Sessions tab to refresh."),
            Fix(problem: "\"claude: command not found\"",
                fix: "The installer puts `claude` in `~/.local/bin`. Add that folder to PATH in `~/.zshrc` on the Mac."),
            Fix(problem: "\"No folders in ~/Projects\"",
                fix: "Make the folder on the Mac, or type a full path in the folder list."),
        ]
    )

    static let terminal = Guide(
        id: "terminal",
        title: "Use the terminal",
        symbol: "keyboard",
        summary: "Keys, replies and commands for a terminal on a small screen.",
        steps: [
            Step(title: "Key bar",
                 text: "The bar above the keyboard has esc, ctrl, tab, arrows and symbols. Tap ctrl, then a letter, to send a control key. For example, ctrl then c stops a command.",
                 symbol: "control"),
            Step(title: "Copy and paste",
                 text: "Select text, then tap Copy at the right of the key bar. With no selection, Copy takes the whole screen. Paste types the clipboard.",
                 symbol: "doc.on.doc"),
            Step(title: "Reply chips",
                 text: "The chips above the terminal type a saved reply and Return, such as `continue`. Edit them in Settings > Snippets.",
                 opens: .settings, symbol: "text.bubble"),
            Step(title: "Command snippets",
                 text: "Saved commands show in the Sessions tab. Tap one to run it in a new terminal on the Mac. The app asks first.",
                 symbol: "bolt"),
            Step(title: "Reconnect",
                 text: "If the network drops, the last screen stays. Tap Reconnect to attach to the same tmux session again.",
                 symbol: "arrow.clockwise"),
        ]
    )
}

/// One guide. `from` is the tab that shows it, so a step does not offer a button to that same tab.
struct GuideView: View {
    var guide: Guide
    var from: AppTab
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showTab) private var showTab

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(guide.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    StepCard(number: index + 1, step: step, opens: step.opens == from ? nil : step.opens) { tab in
                        dismiss()
                        showTab(tab)
                    }
                }

                if !guide.fixes.isEmpty {
                    SectionLabel(guide.fixesTitle)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(guide.fixes.enumerated()), id: \.offset) { index, fix in
                            if index > 0 { Divider().overlay(Theme.stroke) }
                            FixRow(fix: fix)
                        }
                    }
                    .card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A guide in a sheet, for tabs that have no navigation stack to push it on.
struct GuideSheet: View {
    var guide: Guide
    var from: AppTab
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GuideView(guide: guide, from: from)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationBackground(Theme.background)
    }
}

private struct StepCard: View {
    var number: Int
    var step: Guide.Step
    var opens: AppTab?
    var onOpen: (AppTab) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            marker
            VStack(alignment: .leading, spacing: 8) {
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(step.text))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let command = step.command {
                    CommandBox(command: command)
                }
                if let opens {
                    Button { onOpen(opens) } label: {
                        Label("Open \(opens.title)", systemImage: "arrow.up.forward")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .card()
    }

    private var marker: some View {
        Group {
            if let symbol = step.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
            } else {
                Text("\(number)")
                    .font(.footnote.weight(.bold))
            }
        }
        .foregroundStyle(Theme.accent)
        .frame(width: 26, height: 26)
        .background(Theme.accent.opacity(0.12), in: Circle())
        .accessibilityHidden(true)
    }
}

/// A command to run on the Mac. Copy puts it on the clipboard, which Universal Clipboard can
/// carry to the Mac.
private struct CommandBox: View {
    var command: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(command)
                .font(Theme.mono)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                UIPasteboard.general.string = command
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(copied ? Theme.online : Theme.textSecondary)
                    .frame(width: 20, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? "Copied" : "Copy command")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

private struct FixRow: View {
    var fix: Guide.Fix

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fix.problem)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(LocalizedStringKey(fix.fix))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

#Preview {
    GuideSheet(guide: .connectMac, from: .sessions)
        .preferredColorScheme(.dark)
}
