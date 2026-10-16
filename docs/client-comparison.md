# Echo, Termius and Blink compared with SSHTerm

Source: public pages read on 2026-10-15 (developer sites, help centers and App Store listings, linked at the end). None of the three apps was installed or tested. "Not documented" means the public pages do not say, so the feature may still exist.

## Does each app match the plan

The plan asked two things about these apps: do they save hosts, and do they support tmux.

All three save hosts. Echo keeps a server list where each entry has a type (ssh or mosh), a `user@hostname[:port]` target and an optional nickname. Termius Starter saves hosts and groups in a local vault, and only the paid Pro plan syncs them. Blink saves an alias, hostname, port, user, password and key per host, plus a raw `ssh_config` field and Mosh options.

None of the three has a tmux interface. Each one treats tmux as something the user types inside the shell. Echo's launch post describes the workflow as SSH in, then attach to a tmux session. Termius suggests a per-host startup command such as `tmux attach -t <name>` or `cd ~/my-project && claude`. Blink's Mosh page suggests tmux inside Mosh to keep scrollback. So SSHTerm's tmux session list and new Claude session picker have no match in these three apps. The closest app found is Attach, a separate App Store app that is a native tmux client for Claude Code and Codex and has no local terminal emulation.

| | Echo | Termius Starter | Blink |
|---|---|---|---|
| Price | $2.99 once | Free. Pro is $15 a month or $119 a year | Subscription, price not checked |
| Saved hosts | Yes | Yes, local only | Yes |
| Keys | Imported keys in the Keychain, Face ID per key. In-app key generation not documented | Generated in the Secure Enclave with Face ID. Ed25519 not named | Key pairs made in the app |
| Mosh | Built in, and can install `mosh-server` on the host | Free | Built in |
| tmux | Typed by the user | Startup command | Typed by the user, inside Mosh |
| Snippets | Not documented | One-tap snippets, free | Snips |
| Extra keys | Esc, Ctrl, Tab, `~ \| / -`, drag for arrows, long-press repeat | Editable bar, drag gestures for arrows | Ctrl, Alt, Esc, arrows, chained modifiers |
| Themes | Over 390 terminal themes, light and dark | Per-connection themes, including Flexoki Light | A few built in, more from a gallery |
| Background | Mosh sessions survive sleep and backgrounding | iOS stops it within 20 to 30 seconds. Live Activities and location access reduce drops | A "Geo" toggle, mechanism not documented |

Echo needs iOS 26 or later. It uses Ghostty's terminal engine.

## Behaviors SSHTerm could add

Termius published eight tips for running coding agents on a phone in May 2026. Some of them, and some of Echo's keyboard behavior, match gaps in SSHTerm. The plan says not to copy another app's UI or branding, and these are behaviors described in public docs, so they fall inside that rule.

1. A Shift+Tab key. Claude Code uses Shift+Tab to cycle its modes (default, accept edits, plan). Added on 2026-10-15: the key after Tab on the key bar sends `ESC [ Z`.
2. Drag gestures for arrow keys. Termius moves up and down with a long press and drag, and left and right by holding Space and dragging. Echo has a similar gesture. This helps in Claude Code's menus. Added: a drag pad on the key bar sends one arrow key for each 18 points of travel. The system keyboard's Space bar is not open to apps, so the Space drag is not possible.
3. Pinch to change the text size. Echo and Blink both do this. Added on 2026-10-15: a pinch steps the size in whole points from 9 to 24 and saves it, so Settings and the next terminal use it.
4. Dictation sent as one paste. Termius has a Paste mode above its key bar, so a dictated prompt reaches the terminal in one piece. Added on 2026-10-15: Write a prompt, on the key bar and in the terminal's tools menu, opens a text box. Insert or Send puts the text in as one bracketed paste, and Send adds Return.
5. Local port forwarding to preview a dev server in the phone's browser. Added on 2026-10-15: Preview a port, in the terminal's tools menu, forwards a port on the phone to the same port on the Mac's localhost over Citadel's direct TCP/IP channels, and opens it in Safari inside the app. Safari stays inside the app because iOS suspends a background app and its listener.
6. Image upload over SFTP, so a screenshot path can go into a prompt. Added on 2026-10-15: Send an image, in the terminal's tools menu, copies a photo to `/tmp/kessik` on the Mac and types its path. A HEIC photo becomes JPEG, because Claude Code does not read HEIC.

Termius's help center confirms the background limit that SSHTerm already plans around. iOS stops background network activity within 20 to 30 seconds, and tmux plus a fast reattach is the answer all three give for plain SSH. Only Mosh keeps the view itself alive, and Mosh waits for a later SSHTerm version.

## Notes for the light theme decision

The app has had Dark, Light and System themes since the light theme commit. Dark is the default. None of the three apps documents a light mode for the app itself. Each one treats light as a terminal color theme that the user picks.

A light terminal has a side effect for Claude Code. Claude Code picks dark or light colors from its `theme` setting, and its `auto` value reads the terminal background with an OSC 11 query when it starts. SwiftTerm answers that query (`reportColor` in its `Terminal.swift`). However, tmux sits between the two, and a Claude session keeps the colors it chose at launch even when the phone later shows it on a different background. An open issue from August 2026 also reports that `auto` picks the opposite theme on some terminals. The result can be Claude Code's dark-theme colors on a white background.

## Sources

- Echo: [product page](https://replay.software/echo), [help](https://replay.software/help/echo), [launch post](https://replay.software/updates/introducing-echo), [App Store](https://apps.apple.com/mx/app/echo-ssh-client/id6758669847)
- Termius: [App Store](https://apps.apple.com/us/app/termius-ssh-mosh-client/id549039908), [background FAQ](https://docs.termius.com/help-center/faq/how-can-i-keep-termius-sessions-alive-in-the-background-on-ios-ipados), [AI agent tips](https://termius.com/blog/8-tips-for-using-ai-agents-on-mobile-in-termius)
- Blink: [docs](https://docs.blink.sh/), [hosts](https://docs.blink.sh/basics/hosts), [customize](https://docs.blink.sh/basics/customize), [Mosh](https://docs.blink.sh/advanced/advanced-mosh)
- Attach: [App Store](https://apps.apple.com/ca/app/attach-ssh-native-tmux/id6760011289)
- Claude Code theme detection: [auto picks the inverse theme](https://claudeissues.com/issue/86048-theme-auto-selects-the-dark-theme-on-a-light-terminal-inverted), [OSC 11 detection](https://claudeissues.com/issue/56848-theme-auto-osc-11-detects-light-terminal-but-syntax-highlighted-code-still-rende)
