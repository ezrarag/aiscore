import SwiftUI

enum SidebarItem: Hashable, Identifiable {
    case philosophy
    case seasonGuide
    case milestones
    case week(UUID)
    
    var id: String {
        switch self {
        case .philosophy: "philosophy"
        case .seasonGuide: "seasonGuide"
        case .milestones: "milestones"
        case .week(let id): id.uuidString
        }
    }
}

struct InstructorStudioView: View {
    @Environment(ScoreStore.self) private var store
    @State private var selectedSidebarItem: SidebarItem? = nil
    @State private var inspector: InspectorTab = .copilot
    @State private var showInspector = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    enum InspectorTab: String, CaseIterable { case copilot = "AI", stage = "Stage", pulse = "Pulse", terminal = "Terminal" }

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedSidebarItem) {
                Section("Overview") {
                    NavigationLink(value: SidebarItem.philosophy) {
                        Label("Philosophy & DNA", systemImage: "brain.headset")
                    }
                    NavigationLink(value: SidebarItem.seasonGuide) {
                        Label("Season Guide", systemImage: "map")
                    }
                    NavigationLink(value: SidebarItem.milestones) {
                        Label("Milestones", systemImage: "flag.checkered")
                    }
                }
                
                Section("Weekly Timeline") {
                    ForEach(store.scores) { score in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("WEEK \(score.week)").font(.caption2.bold()).foregroundStyle(.secondary)
                            Text(score.title).lineLimit(2)
                        }
                        .tag(SidebarItem.week(score.id))
                        .contextMenu {
                            Button(role: .destructive) {
                                store.deleteWeek(id: score.id)
                            } label: {
                                Label("Delete Week", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.clear)
            .safeAreaInset(edge: .bottom) { Button("New week", systemImage: "plus") { store.addWeek() }.padding() }
            .navigationSplitViewColumnWidth(min: 210, ideal: 250)
        } detail: {
            Group {
                #if os(macOS)
                HSplitView {
                    detailContentView
                    if showInspector && shouldShowInspector { InspectorView(tab: $inspector).frame(minWidth: 300, idealWidth: 370, maxWidth: 460) }
                }
                #else
                HStack(spacing: 0) {
                    detailContentView
                    if showInspector && shouldShowInspector { InspectorView(tab: $inspector).frame(minWidth: 300, idealWidth: 370, maxWidth: 460) }
                }
                #endif
            }
            .toolbar {
                ToolbarItemGroup {
                    if shouldShowInspector {
                        Picker("Panel", selection: $inspector) {
                            ForEach(InspectorTab.allCases, id: \.self) { tab in
                                #if os(iOS)
                                if tab != .terminal { Text(tab.rawValue).tag(tab) }
                                #else
                                Text(tab.rawValue).tag(tab)
                                #endif
                            }
                        }.pickerStyle(.segmented).frame(maxWidth: 340)
                        Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                    }
                    Button("Log out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { store.signOut() }
                }
            }
            .onAppear {
                if selectedSidebarItem == nil, let firstWeek = store.scores.first {
                    selectedSidebarItem = .week(firstWeek.id)
                }
            }
        }
    }

    @ViewBuilder
    private var detailContentView: some View {
        @Bindable var store = store
        switch selectedSidebarItem {
        case .philosophy:
            PhilosophyDNAView()
        case .seasonGuide:
            SeasonGuideView()
        case .milestones:
            MilestonesView()
        case .week(let id):
            if let index = store.scores.firstIndex(where: { $0.id == id }) {
                ScoreTimelineView(score: $store.scores[index])
            } else {
                ContentUnavailableView("Choose a score", systemImage: "music.note.list")
            }
        case nil:
            ContentUnavailableView("Choose a view", systemImage: "sidebar.left")
        }
    }

    private var shouldShowInspector: Bool {
        if case .week = selectedSidebarItem { return true }
        return false
    }
}

private struct InspectorView: View {
    @Binding var tab: InstructorStudioView.InspectorTab
    var body: some View {
        Group {
            switch tab {
            case .copilot: AICopilotView()
            case .stage: BackgroundStudioView()
            case .pulse: PulseView()
            case .terminal:
                #if os(macOS)
                TerminalView()
                #else
                ContentUnavailableView("Terminal is available on Mac", systemImage: "terminal")
                #endif
            }
        }.background(.regularMaterial)
    }
}
