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

    enum InspectorTab: String, CaseIterable { case copilot = "AI", changes = "Changes", stage = "Stage", pulse = "Pulse", terminal = "Terminal" }

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
            .onChange(of: store.slideImportStatus) { _, status in
                if status != nil {
                    inspector = .changes
                    showInspector = true
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
            case .changes: SlideImportReviewView()
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

private struct SlideImportReviewView: View {
    @Environment(ScoreStore.self) private var store
    @State private var expandedChanges: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Import changes", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                if let preview = store.pendingSlideImport {
                    Text("\(preview.changes.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.blue.opacity(0.2), in: Capsule())
                }
            }
            .padding()
            Divider()

            if let progress = store.slideImportProgress, store.pendingSlideImport == nil {
                VStack(alignment: .leading, spacing: 14) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text(store.slideImportStatus ?? "Preparing import…")
                        .font(.subheadline.weight(.medium))
                    Text("You can continue viewing the score while the document is analyzed. No slide changes are applied until you review and confirm them here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                Spacer()
            } else if let preview = store.pendingSlideImport {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(preview.sourceName).font(.subheadline.bold()).lineLimit(2)
                        HStack {
                            Label("\(preview.updateCount) updates", systemImage: "pencil")
                            Label("\(preview.addCount) additions", systemImage: "plus")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                    Divider()
                    if preview.changes.isEmpty {
                        ContentUnavailableView("No changes needed", systemImage: "checkmark.circle", description: Text("The imported description is already represented in this score."))
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(preview.changes) { change in
                                    DisclosureGroup(isExpanded: Binding(
                                        get: { expandedChanges.contains(change.id) },
                                        set: { expanded in
                                            if expanded { expandedChanges.insert(change.id) }
                                            else { expandedChanges.remove(change.id) }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 10) {
                                            if let oldBody = change.oldBody, oldBody != change.newBody {
                                                diffSection("Current slide text", text: oldBody, color: .red)
                                            }
                                            diffSection(change.kind == .add ? "Proposed slide text" : "New slide text", text: change.newBody, color: .green)
                                            if let oldNotes = change.oldNotes, oldNotes != change.newNotes {
                                                diffSection("Current notes", text: oldNotes, color: .red)
                                            }
                                            if !change.newNotes.isEmpty {
                                                diffSection("New notes", text: change.newNotes, color: .green)
                                            }
                                        }
                                        .padding(.top, 8)
                                    } label: {
                                        HStack(alignment: .top) {
                                            Text(change.kind.rawValue.uppercased())
                                                .font(.caption2.bold())
                                                .foregroundStyle(change.kind == .add ? .green : .orange)
                                            Text(change.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                        }
                                    }
                                    .padding(12)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding()
                        }
                    }

                    Divider()
                    HStack {
                        Button("Discard", role: .destructive) { store.discardPendingSlideImport() }
                        Spacer()
                        Button("Apply \(preview.changes.count) Changes") { store.applyPendingSlideImport() }
                            .buttonStyle(.borderedProminent)
                            .disabled(preview.changes.isEmpty)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("No pending import", systemImage: "doc.badge.plus", description: Text("Import a slide-description PDF to see progress and review proposed changes here."))
            }
        }
    }

    private func diffSection(_ title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(color)
            Text(text.isEmpty ? "(empty)" : text)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
