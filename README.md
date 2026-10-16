# Kessik

Kessik is an iPhone app that opens Claude Code on a Mac over SSH. It starts each Claude Code session inside tmux, so the session keeps running on the Mac when the phone locks, loses signal or closes the terminal. The phone attaches to the same session later.

The app is written in SwiftUI. It uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for the terminal view and [Citadel](https://github.com/orlandos-nl/Citadel) for the SSH client. It has no server part: the Mac needs only Remote Login, tmux and Claude Code.

## What it does

### Sessions

The Sessions tab lists the tmux sessions on the Mac, newest first, with the folder each one runs in. Tapping a session attaches to it, and touching and holding a session kills it.

New Claude session opens a list of the folders in `~/Projects` on the Mac, most recently changed first. A path typed into the list works for any other folder. The app names the tmux session after the folder and runs `tmux new -A -s <name> -c <folder> claude --remote-control <name>`. The `-A` flag means that picking the same folder again attaches to the session that already exists.

The `--remote-control` flag starts Claude Code with Remote Control on, and the new session shows in the Claude app under Code and at claude.ai/code under the folder name. When a new session opens, a card asks the user to open the Claude app on the phone, with claude.ai/code as the fallback when the app is not installed. The terminal behind the card still works, but the card makes the Claude app the main way to talk to Claude from the phone. Remote Control needs a claude.ai login on the Mac. If the login is an API key, Claude Code still starts and shows a Remote Control error in the terminal.

### Terminal

A bar above the keyboard holds the keys a phone keyboard lacks: esc, ctrl, tab, shift+tab, four arrow keys that repeat while held, and nine shell symbols (`| ~ / - ` $ & * \`). Claude Code cycles its modes with shift+tab. Ctrl works as a toggle, so ctrl and then c stops a command. The bar also has copy, paste and a button that hides the keyboard. Copy takes the selection, or the visible screen when nothing is selected. Key taps give a haptic tap, which Settings can turn off.

A swipe up scrolls the history of the tmux session, because the app turns on tmux mouse mode for each session it attaches to. A button then returns to the newest output. Pinching the terminal changes the text size in whole points from 9 to 24, and the Settings stepper uses the same range. The app theme is Dark, Light or System in Settings > Appearance, and Dark is the default.

Settings > Appearance also sets the terminal colors, from built-in palettes or iTerm2 color presets the user imports. Each Mac can have its own terminal colors, set in the Mac's editor in Settings, and Same as app keeps the colors from Appearance. If an imported palette that a Mac uses is deleted, that Mac goes back to the colors from Appearance. Claude Code picks its dark or light colors when it starts, so a Claude session on a Mac with light terminal colors can still show its dark colors.

When Claude Code shows a numbered menu, such as a permission prompt, the app reads the menu from the screen and shows one button per option. A tap on a button sends that option's number.

The pencil key on the bar opens a text box for a long or dictated prompt. Insert puts the text into the terminal as one paste, so a new line in it does not send the prompt early, and Send adds Return. The same box is in the tools menu at the top right of the terminal, which also holds three more items. Send an image copies a photo to `/tmp/kessik` on the Mac over SFTP and types its path, so the image can go into a Claude prompt. Preview a port forwards a port on the phone to the same port on the Mac over the SSH connection, and opens it in Safari inside the app, so a dev server that listens only on the Mac shows on the phone. The forward closes with the terminal. Search the scrollback reads up to the last 10,000 lines of the tmux session with `tmux capture-pane` and shows them. Text typed in its search field shows only the lines that hold it, with the line before and after, a count of the matches and each match highlighted. The search is plain text and ignores case, and a tap on a line copies it. The item shows only for a tmux session, because tmux holds the history.

Reply chips above the terminal type a saved reply and Return, such as `continue` or `yes`. Command snippets appear in the Sessions tab, and each one runs in a new terminal on the Mac after the app asks. Both kinds are edited in Settings > Snippets.

### Logging in

The Mac is set once in Settings, by hostname, username and port. The app logs in with a key or with a password. A key is made in Settings > SSH key, where Key type picks one of two kinds. An ed25519 key keeps its private half in the iPhone Keychain. A Secure Enclave key is a P-256 key (`ecdsa-sha2-nistp256`) whose private half never leaves the iPhone's Secure Enclave, and each login asks for Face ID before the key signs. A reset of Face ID stops that key working, so a new one must be made and added again. On a device without a Secure Enclave, the picker is off and the app uses ed25519. With Ed25519 picked, Import key takes an existing ed25519 private key in OpenSSH format, pasted as text or picked from Files. A key with a passphrase asks for it once, and the app saves the key without it. The app does not import RSA or ECDSA keys. The imported key replaces the app's ed25519 key, after a confirmation when there is one already. Settings shows the public half of the key and its SHA256 fingerprint. The Add to button appends the public half to `~/.ssh/authorized_keys` on the Mac over a connection that is already open. At login the app tries the key first and then a saved password. Saved passwords go to the Keychain, and a Settings toggle turns that off.

The first host key a Mac presents is saved. If a later connection presents a different key, the app stops the connection and says that the host key changed.

A Mac that the phone cannot reach directly can have a jump host, set under Jump host in the Mac's settings by hostname, port and username, like `ssh -J`. The app logs in to the jump host first and then to the Mac through it. Both logins try the key first and then the saved password for that host, and the jump host's password is saved from the same settings. The app checks the host key of the jump host and of the Mac separately, each against the key first saved for that host, and a changed key on either one stops the connection. An error message starts with "Jump host:" or "Mac, through" to show which login failed.

### Staying connected

iOS can end a socket without telling the app. The app checks the connection when it returns to the foreground, after a network change and every 30 seconds. When the connection is gone, the last screen stays visible and a Reconnect button attaches to the same tmux session again. A failure message says when the phone itself is offline.

### Reaching the Mac

In Settings, the app searches the current Wi-Fi for Macs that have Remote Login on, using Bonjour. A `.local` name works on that Wi-Fi only. After a login to such a name, the app asks the Mac for its Tailscale address and offers to switch to it, because that address works on any network while [Tailscale](https://tailscale.com) is on for both devices.

### Guides

Four guides are built into the app, in Settings > Guides and behind the How to connect button in the Sessions tab. They cover connecting to a Mac, logging in without a password, setting up Claude Code on the Mac and using the terminal. Each guide ends with fixes for the errors the app shows.

## Requirements

The phone must be an iPhone running iOS 17.0 or later. The app does not target iPad.

The Mac needs three things:

1. Remote Login turned on in System Settings > General > Sharing.
2. [tmux](https://github.com/tmux/tmux), installed with Homebrew: `brew install tmux`. The app looks for it in `/opt/homebrew/bin` and `/usr/local/bin`.
3. [Claude Code](https://docs.claude.com/en/docs/claude-code/overview), installed with `curl -fsSL https://claude.ai/install.sh | bash` and signed in once by running `claude` in Terminal.

Tailscale is optional. It is the way to reach the Mac away from home.

## Build and run

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen), and `Kessik.xcodeproj` is not committed. The app was built with Xcode 26.6.

```bash
brew install xcodegen
git clone https://github.com/zach-short/kessik.git
cd kessik
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Edit `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` to your Apple team ID and `SSHTERM_BUNDLE_ID` to a bundle ID you own. The committed `Config/Base.xcconfig` sets the placeholder `com.example.kessik`, and Git ignores `Local.xcconfig`, so your values stay out of the repository. Then generate the project and open it.

```bash
xcodegen generate
open Kessik.xcodeproj
```

Pick a simulator or a connected iPhone in Xcode and run the Kessik scheme. Builds from the command line with `xcodebuild` need the flags `-skipPackagePluginValidation` and `-skipMacroValidation`, because SwiftTerm's build plugin fails validation without them.

## Dependencies

| Package | Version | Used for |
|---|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | 1.19.0 | Terminal view and escape sequence handling |
| [Citadel](https://github.com/orlandos-nl/Citadel) | 0.12.0 | SSH client |
| [swift-nio-ssh](https://github.com/Joannis/swift-nio-ssh) | 0.3.x | Host key checks and private key types (`NIOSSH`) |
| [swift-nio](https://github.com/apple/swift-nio) | 2.81.0 or later | Networking types (`NIOCore`, `NIOPosix`) |
| [lottie-spm](https://github.com/airbnb/lottie-spm) | 4.6.1 | Splash and connecting animations |

Citadel is pinned to 0.12.0 because version 0.12.1 moved NIOSSH to a third-party fork, while 0.12.0 uses the maintainer's fork. The app declares swift-nio-ssh itself so that it can import `NIOSSH` for the host key check.

## Project layout

`Kessik/SSH` holds the connection code: the SSH session, the tmux commands and their parsers, the Keychain wrappers, the host key store, the Bonjour search and the network monitor. `Kessik/Features` holds one folder per screen area: Hosts, Sessions, Terminal, Settings and Guides. `Kessik/Components` holds shared views, and `Kessik/Theme` holds colors and fonts. The guide text lives in `Kessik/Features/Guides/Guides.swift` and must match the labels and error messages the app shows.

The two Lottie files in `Kessik/Resources/Animations` are generated. Edit `Tools/make_animations.py` and run `python3 Tools/make_animations.py` to rewrite them. Do not edit the JSON by hand.

## Notes

[docs/client-comparison.md](docs/client-comparison.md) compares Kessik with Echo, Termius and Blink from their public pages. None of the three apps was installed or tested for it, so a feature marked "not documented" may still exist.

Kessik does not support Mosh. The app saves one Mac at a time.
