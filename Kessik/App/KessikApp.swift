import SwiftUI

@main
struct KessikApp: App {
    @State private var store: AppStore
    @State private var link: MacLink
    @State private var showSplash = true
    @AppStorage(SettingsKey.appearance) private var appearance = AppAppearance.dark

    init() {
        let store = AppStore()
        _store = State(initialValue: store)
        _link = State(initialValue: MacLink(host: store.hosts.first ?? .unset))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                if showSplash {
                    SplashView {
                        withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .environment(store)
            .environment(link)
            .preferredColorScheme(appearance.colorScheme)
            .tint(Theme.accent)
            .onChange(of: store.snippets) { _, snippets in SavedSnippets.save(snippets) }
        }
    }
}
