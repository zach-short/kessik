# Raw device captures

This folder holds the ten screenshots behind the App Store frames: `01.png` to `10.png`, matching the ten frames in `../board.html`. The board draws each capture inside a device frame. If a file is missing, that frame draws a placeholder mock. A placeholder must never reach App Store Connect, because guideline 2.3.3 requires screenshots to show the app in actual use. `scripts/store-shots.sh` prints which frames still have no capture.

Each frame's caption is a claim, so a capture has to show what its caption says. If a capture cannot show it, change the caption in `../board.html` and leave the capture alone.

## Before you start

The App Store slot for iPhone is 1320x2868 (6.9 inch). The iPhone 17 Pro Max simulator captures exactly that size. A real iPhone 17 Pro captures 1206x2622, and the board scales it up a little. Frame 10 needs a real iPhone, because the Simulator has no Secure Enclave and the Key type picker is off there.

An app in the Simulator reaches the Mac that runs it at `localhost`. Turn on Remote Login, then add a Mac in Settings with the hostname `localhost` and your own username. Use a throwaway project folder, so no private path, hostname or token shows in a frame.

Set a clean status bar, shoot each frame, then clear the override:

```bash
xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
xcrun simctl io booted screenshot design/store/raw/01.png
xcrun simctl status_bar booted clear
```

Render the set with `scripts/store-shots.sh`. It writes ten JPEG files to `build/store-shots/`, and those are the files to upload.

## The ten frames

| Frame | Caption | What the capture shows |
|---|---|---|
| 01 | Claude Code, from your iPhone. | The terminal with Claude Code partway through a task. |
| 02 | Lock the phone. The work goes on. | The Sessions tab with two or three running tmux sessions. |
| 03 | Tap the option, not the number. | A Claude permission prompt with the option buttons showing. |
| 04 | The keys a phone forgot. | The terminal with the keyboard up and the whole key bar in view. |
| 05 | Dictate it. Send it once. | The prompt box open with a few lines of text in it. |
| 06 | Photos and files, to the Mac. | The terminal after Send an image, with the typed path in the prompt line. |
| 07 | See the dev server on the phone. | Preview a port open, with a real dev server page in Safari. |
| 08 | Search the last 10,000 lines. | Search the scrollback with a query typed and the matches highlighted. |
| 09 | Every Mac, its own setup. | One Mac's editor (Settings, the info button on a Mac) with Terminal colors, Start command and Jump host in view. |
| 10 | Keys that never leave the phone. | Settings, SSH key, with Key type set to Secure Enclave, shot on a real iPhone. |
