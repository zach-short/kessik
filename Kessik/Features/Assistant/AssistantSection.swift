import SwiftUI

/// Settings > Assistant: turns the tab on and names the Mac user the assistant runs as.
struct AssistantSection: View {
    @Environment(AssistantLink.self) private var assistant
    @Environment(AppStore.self) private var store
    @AppStorage(SettingsKey.assistantEnabled) private var enabled = false
    @AppStorage(SettingsKey.assistantUser) private var user = "agent"
    @State private var checking = false
    @State private var result: String?

    var body: some View {
        Section {
            Toggle("Assistant tab", isOn: $enabled)
            if enabled {
                LabeledContent("Mac user") {
                    TextField("agent", text: $user)
                        .multilineTextAlignment(.trailing)
                        .font(Theme.mono)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        Text("Check connection")
                        Spacer()
                        if checking { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(checking || store.activeMac == nil)
                if let result {
                    Text(result)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("Assistant")
        } footer: {
            Text("A local assistant on your Mac. Chats and facts stay on the Mac, and the app logs in as its own user, so Claude sessions cannot read them. Set it up on the Mac with `make assistant-install` in the home-server folder.")
        }
        .onChange(of: user) { assistant.disconnect() }
    }

    private func check() async {
        guard let mac = store.activeMac else { return }
        checking = true
        defer { checking = false }
        do {
            let ping = try await assistant.call(AssistantReply.Ping.self, to: mac, user: user, "ping")
            result = "Connected. \(ping.facts) facts, \(ping.repos) repos."
        } catch {
            result = SSHSession.message(for: error, host: AssistantLink.host(for: mac, user: user))
        }
    }
}
