import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case hosts, sessions, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hosts: "Hosts"
        case .sessions: "Sessions"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .hosts: "server.rack"
        case .sessions: "terminal"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @State private var tab: AppTab = .hosts

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch tab {
            case .hosts: HostsView()
            case .sessions: SessionsView()
            case .settings: SettingsView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            PillTabBar(selection: $tab)
                .padding(.bottom, 4)
        }
    }
}

#Preview {
    RootView()
        .environment(AppStore.preview)
        .environment(MacLink(host: AppStore.preview.hosts[0]))
        .preferredColorScheme(.dark)
}
