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

extension EnvironmentValues {
    /// Switches the bottom tab, for links such as "Set up in Settings".
    @Entry var showTab: (AppTab) -> Void = { _ in }
}

struct RootView: View {
    @Environment(MacLink.self) private var link
    @Environment(\.scenePhase) private var scenePhase
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
        .environment(\.showTab) { tab = $0 }
        .safeAreaInset(edge: .bottom) {
            PillTabBar(selection: $tab)
                .padding(.bottom, 4)
        }
        // A socket can die in silence during sleep or a network switch. Check the Sessions link
        // then, and on a timer, so a dead Mac shows a message instead of a hang.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { link.checkAlive() }
        }
        .onChange(of: NetworkMonitor.shared.changes) { link.checkAlive() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                // Read live: a captured `scenePhase` keeps the value from when the task started.
                if UIApplication.shared.applicationState == .active { link.checkAlive() }
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppStore.preview)
        .environment(MacLink(host: AppStore.preview.hosts[0]))
        .preferredColorScheme(.dark)
}
