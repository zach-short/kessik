import SwiftUI

/// Shown after a login to a Mac found on Wi-Fi. Its `.local` name works on that Wi-Fi only, so this
/// offers the Mac's Tailscale address, which works on any network. "Not now" hides it for that name.
struct TailscaleOffer: View {
    @Environment(AppStore.self) private var store
    @Environment(MacLink.self) private var link
    @AppStorage("tailscaleOfferDismissed") private var dismissed = ""
    @State private var checking = false
    @State private var problem: String?
    @State private var guide: Guide?

    var body: some View {
        if link.host.isLocalName, dismissed != link.host.hostname {
            if let address = link.tailscaleAddress {
                card(icon: "network",
                     title: "Use this Mac away from home",
                     text: "`\(link.host.hostname)` works only on this Wi-Fi. The Mac's Tailscale address, `\(address)`, works on any network while Tailscale is on.") {
                    Button {
                        Task { await use(address) }
                    } label: {
                        Group {
                            if checking { ProgressView() } else { Text("Use \(address)") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(checking)
                }
            } else if link.tailscaleMissing {
                card(icon: "wifi",
                     title: "This Mac works on this Wi-Fi only",
                     text: "To connect away from home, put the Mac and this phone on Tailscale. The app finds the Mac's address the next time you connect.") {
                    Button {
                        guide = .connectMac
                    } label: {
                        Text("How to connect").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.textPrimary)
                }
            }
        }
    }

    private func card(icon: String, title: String, text: String,
                      @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(LocalizedStringKey(text))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                action()
                Button("Not now") { dismissed = link.host.hostname }
                    .buttonStyle(.bordered)
                    .tint(Theme.textPrimary)
            }
            .controlSize(.regular)
        }
        .padding(16)
        .card()
        .sheet(item: $guide) { GuideSheet(guide: $0, from: .sessions) }
    }

    /// Checks that this phone reaches the address first, so a phone without Tailscale on keeps the
    /// address that works. The saved host key and password carry over to the new address.
    private func use(_ address: String) async {
        checking = true
        problem = nil
        defer { checking = false }
        let old = link.host
        var host = old
        host.hostname = address
        guard await MacFinder.canReach(address, port: host.port) else {
            problem = "This phone cannot reach \(address). Turn on Tailscale on this phone, then try again."
            return
        }
        TOFUHostKeyValidator.copyTrust(from: old, to: host)
        if let password = SavedPassword.get(for: old) {
            SavedPassword.save(password, for: host)
        }
        SavedMac.save(host)
        store.hosts = [host]
        link.use(host)
        if Credentials.available(for: host) {
            link.connect(password: nil)
        }
    }
}
