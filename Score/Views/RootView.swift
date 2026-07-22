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
        .overlay(alignment: .topTrailing) {
            if store.account != nil {
                Menu {
                    Button {
                        withAnimation(.spring) {
                            if store.roleOverride == nil {
                                store.roleOverride = (store.account?.role == .instructor) ? .student : .instructor
                            } else {
                                store.roleOverride = (store.roleOverride == .instructor) ? .student : .instructor
                            }
                        }
                    } label: {
                        Label("Act as \(store.currentRole == .instructor ? "Student" : "Instructor")", systemImage: "person.leftright")
                    }
                    
                    if store.currentRole == .student {
                        if let activeSlide = store.activeSlide, activeSlide.liveQuestion != nil {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    store.showQuestion.toggle()
                                }
                            } label: {
                                Label(store.showQuestion ? "Hide Provocation" : "Show Provocation", systemImage: "questionmark.circle")
                            }
                        }
                        
                        Button {
                            withAnimation(.snappy) {
                                store.isFullscreen.toggle()
                            }
                        } label: {
                            Label(store.isFullscreen ? "Exit Fullscreen" : "Enter Fullscreen", systemImage: store.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        }
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundStyle(.cyan)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(radius: 2)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .padding(10)
            }
        }
        .onAppear {
            store.startSyncLoop()
        }
    }
}

