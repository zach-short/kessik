import SwiftUI

/// What the big pad in the Remote tab does.
enum RemotePad: String, CaseIterable, Identifiable {
    case pointer, arrows

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pointer: "Pointer"
        case .arrows: "D-pad"
        }
    }
}

/// The Remote tab: a remote control for a Mac that is connected to a TV or monitor. A pad moves
/// the pointer or sends arrow keys, and the buttons below it send Back, Home, Search, volume and
/// playback keys.
struct RemoteView: View {
    @Environment(AppStore.self) private var store
    @Environment(MacLink.self) private var link
    @Environment(RemoteLink.self) private var remote
    @Environment(\.showTab) private var showTab
    @AppStorage(SettingsKey.remotePad) private var pad = RemotePad.pointer
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @State private var typing = false
    @State private var taps = 0

    var body: some View {
        VStack(spacing: 14) {
            header
            notice
            controls
                .disabled(!remote.isConnected)
                .opacity(remote.isConnected ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Theme.background)
        .background {
            KeyCatcher(active: $typing) { remote.send($0) }
                .frame(width: 1, height: 1)
                .opacity(0)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps) { _, _ in hapticsEnabled }
        // The Sessions login carries the remote. Connect when it is up, and again after it comes back.
        .task(id: link.state == .connected) {
            if link.state == .connected {
                await remote.connect(through: link)
            } else {
                remote.disconnect()
                link.connectSavedOnce()
            }
        }
        .onChange(of: remote.isConnected) { _, connected in
            if !connected { typing = false }
        }
        .onDisappear {
            typing = false
            remote.disconnect()
        }
    }

    // MARK: Parts

    /// The pad and the buttons. They are off until the Mac has accepted the phone.
    private var controls: some View {
        VStack(spacing: 14) {
            padSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 120)
            Picker("Pad", selection: $pad) {
                ForEach(RemotePad.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                RemoteButtonView(symbol: "arrow.left", label: "Back") { press(.action(.back)) }
                RemoteButtonView(symbol: "house", label: "Home") { press(.action(.home)) }
                RemoteButtonView(symbol: "magnifyingglass", label: "Search") {
                    press(.action(.search))
                    // Spotlight is open on the Mac, so the next thing is to type.
                    typing = true
                }
            }
            // The keyboard takes half the screen. The pad and the first row matter more than these.
            if !typing {
                HStack(spacing: 10) {
                    RemoteButtonView(symbol: "speaker.minus", label: "Volume down", repeats: true) { press(.action(.volumeDown)) }
                    RemoteButtonView(symbol: "speaker.slash", label: "Mute") { press(.action(.mute)) }
                    RemoteButtonView(symbol: "speaker.plus", label: "Volume up", repeats: true) { press(.action(.volumeUp)) }
                }
                HStack(spacing: 10) {
                    RemoteButtonView(symbol: "backward.fill", label: "Previous") { press(.action(.previous)) }
                    RemoteButtonView(symbol: "playpause.fill", label: "Play or pause") { press(.action(.playPause)) }
                    RemoteButtonView(symbol: "forward.fill", label: "Next") { press(.action(.next)) }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                press(.action(.power))
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke))
            }
            .accessibilityLabel("Sleep or wake the display")
            .disabled(!remote.isConnected)

            Spacer()
            VStack(spacing: 2) {
                Text(store.activeMac?.name ?? "Remote")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    StatusDot(status: remote.isConnected ? .online : .unknown)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()

            Button {
                typing.toggle()
            } label: {
                Image(systemName: typing ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke))
            }
            .accessibilityLabel(typing ? "Hide the keyboard" : "Type on the Mac")
            .disabled(!remote.isConnected)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
    }

    private var status: String {
        switch remote.state {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .idle, .failed: link.state == .connecting ? "Connecting" : "Not connected"
        }
    }

    /// One line that says what stops the remote, with the button that fixes it.
    @ViewBuilder
    private var notice: some View {
        Group {
            if store.activeMac == nil {
                RemoteNotice(text: "Add your Mac in Settings.", action: "Open Settings") { showTab(.settings) }
            } else if case .failed(let message) = remote.state {
                RemoteNotice(text: message, action: "Retry") {
                    Task { await remote.connect(through: link) }
                }
            } else if case .connected(trusted: false) = remote.state {
                RemoteNotice(text: "The Mac ignores the remote until you allow Kessik Remote. On the Mac, open System Settings > Privacy & Security > Accessibility and turn on Kessik Remote.",
                             action: nil) {}
            } else if link.state != .connected, link.state != .connecting {
                RemoteNotice(text: "Log in to the Mac on the Sessions tab.", action: "Open Sessions") { showTab(.sessions) }
            }
        }
    }

    @ViewBuilder
    private var padSurface: some View {
        switch pad {
        case .pointer:
            Trackpad(send: { remote.send($0) }, tapped: { taps += 1 })
                .overlay(alignment: .bottom) {
                    Text("Drag to move. Tap to click. Two fingers scroll. Touch and hold to drag.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .allowsHitTesting(false)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.stroke))
                .accessibilityLabel("Trackpad")
        case .arrows:
            DPad { press(.key($0)) }
        }
    }

    private func press(_ command: RemoteCommand) {
        taps += 1
        remote.send(command)
    }
}

/// A round pad with four arrow keys and OK in the middle. A held arrow repeats.
private struct DPad: View {
    var press: (RemoteKey) -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .overlay(Circle().strokeBorder(Theme.stroke))
                arrow(.up, "chevron.up", side: side).offset(y: -side * 0.33)
                arrow(.down, "chevron.down", side: side).offset(y: side * 0.33)
                arrow(.left, "chevron.left", side: side).offset(x: -side * 0.33)
                arrow(.right, "chevron.right", side: side).offset(x: side * 0.33)
                Button {
                    press(.enter)
                } label: {
                    Text("OK")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: side * 0.34, height: side * 0.34)
                        .background(Theme.surfaceRaised, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.stroke))
                        .contentShape(Circle())
                }
                .accessibilityLabel("OK")
            }
            .buttonStyle(.plain)
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private func arrow(_ key: RemoteKey, _ symbol: String, side: CGFloat) -> some View {
        Button {
            press(key)
        } label: {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: side * 0.3, height: side * 0.3)
                .contentShape(Rectangle())
        }
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(key.rawValue.capitalized)
    }
}

private struct RemoteButtonView: View {
    var symbol: String
    var label: String
    var repeats = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .card()
                .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(repeats ? .enabled : .disabled)
        .accessibilityLabel(label)
    }
}

private struct RemoteNotice: View {
    var text: String
    var action: String?
    var run: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action, action: run)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .card()
    }
}

/// Settings > Remote: turns the tab on.
struct RemoteSection: View {
    @AppStorage(SettingsKey.remoteEnabled) private var enabled = false

    var body: some View {
        Section {
            Toggle("Remote tab", isOn: $enabled)
        } header: {
            Text("Remote")
        } footer: {
            Text("A remote control for a Mac that is connected to a TV or monitor: a trackpad, arrow keys, volume and playback. It needs Kessik Remote on the Mac. Run `scripts/kessik remote` in the Kessik folder on the Mac, then allow Kessik Remote in System Settings > Privacy & Security > Accessibility.")
        }
    }
}

#Preview {
    RemoteView()
        .environment(AppStore.preview)
        .environment(MacLink(host: AppStore.preview.hosts[0]))
        .environment(RemoteLink())
        .preferredColorScheme(.dark)
}
