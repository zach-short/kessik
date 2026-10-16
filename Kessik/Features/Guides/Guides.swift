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
                 text: "On the Mac's Wi-Fi, tap Find Macs on this Wi-Fi in Settings and pick the Mac. Or open Tailscale on this phone and use the Mac's name, such as `my-mac.tailnet-name.ts.net`, or its 100.x address.",
                 opens: .settings),
            Step(title: "Find the username",
                 text: "On the Mac, open Terminal and run this command. It prints the short username.",
                 command: "whoami"),
            Step(title: "Save the Mac in Settings",
                 text: "Enter the hostname and the username. Leave the port empty to use 22. Tap Save.",
                 opens: .settings),
            Step(title: "Connect",
                 text: "In the Sessions tab, type the Mac's login password and tap Connect. The first connection saves the Mac's host key. If that key changes later, the app stops the connection.",
                 opens: .sessions),
            Step(title: "Use it away from home",
                 text: "A Mac found on Wi-Fi has a `.local` name, which works only on that Wi-Fi. After you connect, the Sessions tab offers the Mac's Tailscale address. Tap it to connect from any network."),
        ],
        fixesTitle: "If it does not connect",
        fixes: [
            Fix(problem: "\"Refused the connection\"",
                fix: "Remote Login is off. Turn it on in System Settings > General > Sharing on the Mac."),
            Fix(problem: "\"Was not found\" or \"did not answer\"",
                fix: "Check that Tailscale is on for this phone and for the Mac. Check that the Mac is awake. A `.local` name works only on the Mac's Wi-Fi."),
            Fix(problem: "No Macs found on this Wi-Fi",
                fix: "Turn on Remote Login on the Mac, and join the same Wi-Fi. Check that Local Network is on for Kessik in iOS Settings > Privacy & Security > Local Network."),
            Fix(problem: "\"The Mac refused the login\"",
                fix: "Check the username, and use the password you type to log in to the Mac."),
            Fix(problem: "An error that starts with \"Jump host:\"",
                fix: "The app did not get past the jump host. Check its hostname, port and username under Jump host in the Mac's settings. Save its password there, or add this phone's key to `~/.ssh/authorized_keys` on the jump host."),
            Fix(problem: "An error that starts with \"Mac, through\"",
                fix: "The jump host worked, and the Mac failed. Use the Mac's name or address as the jump host sees it. The jump host must allow TCP forwarding (`AllowTcpForwarding yes`)."),
        ]
    )

    static let sshKey = Guide(
        id: "ssh-key",
        title: "Log in without a password",
        symbol: "key",
        summary: "Add this phone's SSH key to the Mac. Then Connect works with an empty password.",
        steps: [
            Step(title: "Make a key",
                 text: "In Settings > SSH key, pick a Key type and tap Generate SSH key. To use an ed25519 key you already have, pick Ed25519 and tap *Import key*, then paste or choose its private key file. An ed25519 key stays in this phone's Keychain. A Secure Enclave key never leaves this iPhone and asks for Face ID at each login. The Mac accepts both kinds with no change to its settings.",
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
            Fix(problem: "Import says the key type is not supported",
                fix: "The app imports ed25519 keys in OpenSSH format only. Make one on the Mac with `ssh-keygen -t ed25519`, or tap Generate SSH key."),
            Fix(problem: "Import says the encryption cannot be read",
                fix: "The app reads keys with a passphrase when they use aes256-ctr, the ssh-keygen default. For other keys, run `ssh-keygen -p -f <file>` on a copy of the key on the Mac, set an empty passphrase, and import the copy."),
            Fix(problem: "The Secure Enclave key stopped working after a Face ID change",
                fix: "A reset of Face ID, or a new appearance, locks the old Secure Enclave key for good. Connect with the password, then tap *New key* and *Add to* again."),
            Fix(problem: "Face ID was canceled at login",
                fix: "The app then skips the key and tries the saved password. Tap Connect again to use the key."),
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
                 text: "In the Sessions tab, tap New Claude session and pick a folder. The tmux session gets the folder's name. Claude Code starts with Remote Control on.",
                 opens: .sessions),
            Step(title: "Chat in the Claude app",
                 text: "Tap Open Claude, or open the Claude app yourself, tap Code and pick the session. No app? Open claude.ai/code in a browser. The terminal in this app also works, but the Claude app is the better place to chat."),
            Step(title: "Come back to it",
                 text: "Close the terminal at any time. Claude keeps running on the Mac. Tap the session in the Sessions tab to attach again. Touch and hold it to kill it."),
        ],
        fixes: [
            Fix(problem: "\"tmux is not installed\"",
                fix: "The app looks for tmux in `/opt/homebrew/bin` and `/usr/local/bin`. Install it with Homebrew, then pull down on the Sessions tab to refresh."),
            Fix(problem: "\"claude: command not found\"",
                fix: "The installer puts `claude` in `~/.local/bin`. Add that folder to PATH in `~/.zshrc` on the Mac."),
            Fix(problem: "The session is not in the Claude app",
                fix: "Remote Control needs a claude.ai login on the Mac (Pro, Max, Team or Enterprise), not an API key. Look for the error in the terminal. Run `/login` in Claude Code to sign in with claude.ai."),
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
            Step(title: "Search the history",
                 text: "In the tools menu at the top right, Search the scrollback reads the last 10,000 lines of the tmux session. Type text to show only the lines that hold it. Tap a line to copy it.",
                 symbol: "magnifyingglass"),
        ],
        fixes: [
            Fix(problem: "\"tmux could not read this session\"",
                fix: "The tmux session closed or was renamed on the Mac. Close the terminal and open the session again from the Sessions tab."),
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
