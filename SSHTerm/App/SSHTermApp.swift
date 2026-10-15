import SwiftUI

@main
struct SSHTermApp: App {
    @State private var store: AppStore
    @State private var link: MacLink

    init() {
        let store = AppStore()
        _store = State(initialValue: store)
        _link = State(initialValue: MacLink(host: store.hosts[0]))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(link)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
