# Kessik

Kessik is an iPhone app that opens Claude Code on a Mac over SSH. It starts each Claude Code session inside tmux, so the session keeps running on the Mac when the phone locks, loses signal or closes the terminal. The phone attaches to the same session later.

The app is written in SwiftUI. It uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for the terminal view and [Citadel](https://github.com/orlandos-nl/Citadel) for the SSH client. It has no server part: the Mac needs only Remote Login, tmux and Claude Code.

## What it does

### Sessions

The Sessions tab lists the tmux sessions on the Mac, newest first, with the folder each one runs in. Tapping a session attaches to it, and touching and holding a session kills it.

New Claude session opens a list of the folders in `~/Projects` on the Mac, most recently changed first. A path typed into the list works for any other folder. The app starts Claude Code in the background, in a tmux session named after the folder, and does not open it. It runs `tmux new-session -d -s <name> -c <folder> claude --remote-control <name>` in the Mac's own login shell, so `claude` is found on the same `PATH` as in Terminal. The app then reads the session's screen for up to eight seconds. If `claude` ended at once, it says so. If Claude Code is asking whether to trust the folder, which it does the first time it opens a folder, the app opens the terminal at once, because only a person can answer, and shows the card when the terminal closes and the session is still running. Otherwise a card asks the user to pick Open Claude or Open terminal. Picking the same folder again starts nothing, and the card says that the session was already running, unless that session is still on the trust question, which opens the terminal.

The `--remote-control` flag starts Claude Code with Remote Control on, and the session shows in the Claude app under Code and at claude.ai/code under the folder name. Open Claude opens the Claude app, with claude.ai/code as the fallback when the app is not installed. Open terminal attaches to the tmux session in Kessik, and tapping a session in the list does the same. Remote Control needs a claude.ai login on the Mac. If the login is an API key, Claude Code still starts and shows a Remote Control error in the terminal. The app finds the trust question by the text Claude Code draws for it ("Yes, I trust this folder", as in Claude Code 2.1.301). If a later version changes that text, the app shows the card instead, and the card says to open the terminal when Claude Code is waiting for an answer.

A Mac can have its own Start command in its settings, such as `codex` or `claude --model opus`. New Claude session then runs that command in place of `claude --remote-control <name>` and opens the terminal at once, because a start command may not have Remote Control: it runs `tmux new -A -s <name> -c <folder> <command>` and attaches.

### Terminal

A bar above the keyboard holds the keys a phone keyboard lacks: esc, ctrl, tab, shift+tab, four arrow keys that repeat while held, and nine shell symbols (`| ~ / - ` $ & * \`). Claude Code cycles its modes with shift+tab. Ctrl works as a toggle, so ctrl and then c stops a command. The bar also has copy, paste and a button that hides the keyboard. Copy takes the selection, or the visible screen when nothing is selected. Key taps give a haptic tap, which Settings can turn off.

A swipe up scrolls the history of the tmux session, because the app turns on tmux mouse mode for each session it attaches to. A button then returns to the newest output. Pinching the terminal changes the text size in whole points from 9 to 24, and the Settings stepper uses the same range. The app theme is Dark, Light or System in Settings > Appearance, and Dark is the default.

Settings > Appearance also sets the terminal colors, from built-in palettes or iTerm2 color presets the user imports. Each Mac can have its own terminal colors, set in the Mac's editor in Settings, and Same as app keeps the colors from Appearance. If an imported palette that a Mac uses is deleted, that Mac goes back to the colors from Appearance. Claude Code picks its dark or light colors when it starts, so a Claude session on a Mac with light terminal colors can still show its dark colors. Appearance also sets the cursor shape, Block, Bar or Underline, and whether it blinks. The default is a blinking block. A program can still change the cursor while it runs.

When Claude Code shows a numbered menu, such as a permission prompt, the app reads the menu from the screen and shows one button per option. A tap on a button sends that option's number.

The pencil key on the bar opens a text box for a long or dictated prompt. Insert puts the text into the terminal as one paste, so a new line in it does not send the prompt early, and Send adds Return. The same box is in the tools menu at the top right of the terminal, which also holds four more items. Send an image copies a photo to `/tmp/kessik` on the Mac over SFTP and types its path, so the image can go into a Claude prompt. Send a file does the same for any file picked in Files, up to 100 MB. The file goes as it is, and its name keeps the original name after a time stamp. Preview a port forwards a port on the phone to the same port on the Mac over the SSH connection, and opens it in Safari inside the app, so a dev server that listens only on the Mac shows on the phone. The forward closes with the terminal. Search the scrollback reads up to the last 10,000 lines of the tmux session with `tmux capture-pane` and shows them. Text typed in its search field shows only the lines that hold it, with the line before and after, a count of the matches and each match highlighted. The search is plain text and ignores case, and a tap on a line copies it. The item shows only for a tmux session, because tmux holds the history.

Reply chips above the terminal type a saved reply and Return, such as `continue` or `yes`. Command snippets appear in the Sessions tab, and each one runs in a new terminal on the Mac after the app asks. Both kinds are edited in Settings > Snippets.

### Logging in

Each Mac is added once in Settings, by hostname, username and port. The Macs section lists every saved Mac. A tap on a Mac makes the Sessions tab use it, the info button edits it and a swipe deletes it. Picking another Mac while one is connected closes that connection. A line pasted into the hostname field, such as `ssh -p 2222 me@my-mac` or `ssh://me@my-mac:2222`, fills the hostname, username and port, and a `-J` option fills the jump host. The app logs in with a key or with a password. A key is made in Settings > SSH key, where Key type picks one of two kinds. An ed25519 key keeps its private half in the iPhone Keychain. A Secure Enclave key is a P-256 key (`ecdsa-sha2-nistp256`) whose private half never leaves the iPhone's Secure Enclave, and each login asks for Face ID before the key signs. A reset of Face ID stops that key working, so a new one must be made and added again. On a device without a Secure Enclave, the picker is off and the app uses ed25519. With Ed25519 picked, Import key takes an existing ed25519 or ECDSA (P-256, P-384 or P-521) private key in OpenSSH format, pasted as text or picked from Files. A key with a passphrase asks for it once, and the app saves the key without it. The app does not import RSA or DSA keys. The imported key replaces the app's key in the Keychain, and the first Key type option then shows its type, such as ECDSA P-384. The import replaces the old key after a confirmation when there is one already. Settings shows the public half of the key and its SHA256 fingerprint. The Add to button appends the public half to `~/.ssh/authorized_keys` on the Mac over a connection that is already open. At login the app tries the key first and then a saved password. Saved passwords go to the Keychain, and a Settings toggle turns that off.

The first host key a Mac presents is saved. If a later connection presents a different key, the app stops the connection and says that the host key changed.

A Mac that the phone cannot reach directly can have a jump host, set under Jump host in the Mac's settings by hostname, port and username, like `ssh -J`. The app logs in to the jump host first and then to the Mac through it. Both logins try the key first and then the saved password for that host, and the jump host's password is saved from the same settings. The app checks the host key of the jump host and of the Mac separately, each against the key first saved for that host, and a changed key on either one stops the connection. An error message starts with "Jump host:" or "Mac, through" to show which login failed.

### Staying connected

iOS can end a socket without telling the app. The app checks the connection when it returns to the foreground, after a network change and every 30 seconds. When the connection is gone, the last screen stays visible and a Reconnect button attaches to the same tmux session again. A failure message says when the phone itself is offline.

### Reaching the Mac

In Settings, the app searches the current Wi-Fi for Macs that have Remote Login on, using Bonjour. A `.local` name or a private Wi-Fi address, such as `192.168.1.20`, works on that Wi-Fi only. After a login to such an address, the app asks the Mac for its Tailscale address and offers to switch to it, because that address works on any network while [Tailscale](https://tailscale.com) is on for both devices. The app reads the address from the Tailscale command line tool, or from the Mac's `utun` interfaces when the tool does not answer. Some networks, such as campus Wi-Fi, give the Mac's Wi-Fi a 100.x address from the range Tailscale uses, so the app also checks a saved 100.x address against the Mac and offers the Tailscale address when the two differ. When a `.local` name or a private address does not answer, the error says that the address works only on the Mac's own network and to use the Tailscale address away from it. The app connects to a Tailscale address (100.64.0.0/10) as it is, without the system resolver. On an IPv6-only cellular network, such as T-Mobile's, the resolver turns an IPv4 address into a NAT64 IPv6 address, which goes out over cellular and not through Tailscale, so the Mac never sees the connection.

### Guides

Four guides are built into the app, in Settings > Guides and behind the How to connect button in the Sessions tab. They cover connecting to a Mac, logging in without a password, setting up Claude Code on the Mac and using the terminal. Each guide ends with fixes for the errors the app shows.

### Changelog

Settings > Changelog lists what changed in each version, newest first, and marks the version of the build in hand. The same notes are at [kessik.com/changelog](https://kessik.com/changelog).

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

## Release notes

`release-notes.json` at the root of the repository is the one copy of what changed in each version. The app bundles it (`Kessik/Models/ReleaseNotes.swift` reads it) and the site imports it at build time (`site/src/pages/changelog.astro`), so the app and kessik.com cannot disagree. Each version has a headline, a lead paragraph and a list of changes, and each change is `new`, `better` or `fixed`, with a short title and a detail of one or two sentences. Newest version first.

Add the entry before `MARKETING_VERSION` in `project.yml` changes. `scripts/archive.sh` refuses to cut a build when the newest entry is not the version in `project.yml`, and `ReleaseNotesTests` fails the same way. The date is the day the version goes out, so set it when the build ships. The site shows a new entry the next time it deploys.

## App Store screenshots

`design/store/board.html` draws the ten App Store frames: a caption, and a capture inside a tilted device, with one line running behind all ten. The captures are `design/store/raw/01.png` to `10.png`, and a frame with no capture draws a placeholder. `design/store/raw/README.md` says what each capture shows and how to take it. Run `scripts/store-shots.sh` to render the frames to `build/store-shots/` as 1320x2868 JPEG files for upload, or `scripts/store-shots.sh 3` for one frame. The script needs Google Chrome, and it says which frames still have no capture. A placeholder must never be uploaded.

## Notes

[docs/client-comparison.md](docs/client-comparison.md) compares Kessik with Echo, Termius and Blink from their public pages. None of the three apps was installed or tested for it, so a feature marked "not documented" may still exist.

Kessik does not support Mosh. The Sessions tab uses one Mac at a time, the one checked in Settings.
