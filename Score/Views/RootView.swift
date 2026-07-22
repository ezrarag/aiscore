import SwiftUI

struct RootView: View {
    @Environment(ScoreStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            if store.account == nil { SignInView() }
            else if store.currentRole == .student { StudentStudioView() }
            else { InstructorStudioView() }
        }
        .background(StudioBackgroundView(background: store.background).ignoresSafeArea())
        .alert("Score", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onAppear {
            store.startSyncLoop()
        }
    }
}
