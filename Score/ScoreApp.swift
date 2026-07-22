import SwiftUI

@main
struct ScoreApp: App {
    @State private var store = ScoreStore()

    var body: some Scene {
#if os(macOS)
        WindowGroup { RootView().environment(store) }
            .defaultSize(width: 1320, height: 820)
            .windowStyle(.hiddenTitleBar)
        Settings { SettingsView().environment(store) }
#else
        WindowGroup { RootView().environment(store) }
#endif
    }
}
