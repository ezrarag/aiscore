import SwiftUI

@main
struct ScoreApp: App {
    @State private var store = ScoreStore()

    var body: some Scene {
#if os(macOS)
        WindowGroup { RootView().environment(store) }
            .defaultSize(width: 1320, height: 820)
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandMenu("View & Navigation") {
                    Button("Switch Role (Student / Instructor)") {
                        if store.currentRole == .instructor {
                            store.roleOverride = .student
                        } else {
                            store.roleOverride = .instructor
                        }
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    
                    Button("Toggle Fullscreen Presentation") {
                        store.isFullscreen.toggle()
                    }
                    .keyboardShortcut("f", modifiers: [.command])
                    
                    Divider()
                    
                    Button("Next Slide") {
                        store.nextSlide()
                    }
                    .keyboardShortcut("]", modifiers: [.command])
                    
                    Button("Previous Slide") {
                        store.prevSlide()
                    }
                    .keyboardShortcut("[", modifiers: [.command])
                    
                    Button("Toggle Live Provocation") {
                        store.showQuestion.toggle()
                    }
                    .keyboardShortcut("q", modifiers: [.command])
                }
            }
        Settings { SettingsView().environment(store) }
#else
        WindowGroup { RootView().environment(store) }
#endif
    }
}
