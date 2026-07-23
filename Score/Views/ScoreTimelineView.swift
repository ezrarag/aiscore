import SwiftUI

struct IdentifiableUUID: Identifiable {
    let id: UUID
}

struct ScoreTimelineView: View {
    @Environment(ScoreStore.self) private var store
    @Binding var score: StudioScore
    @State private var expanded: Set<UUID> = []
    @State private var recordingSlideID: UUID? = nil
    @State private var generatingImageForSlideID: UUID? = nil
    @State private var csvURLString = ""
    @State private var showServerConfig = false
    @State private var showKeynoteThemePicker = false
    @State private var editingProvocationSlideID: UUID? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Score title", text: $score.title).font(.largeTitle.bold()).textFieldStyle(.plain)
                        TextField("Big question", text: $score.bigQuestion, axis: .vertical).font(.title3).textFieldStyle(.plain).foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Menu {
                        Button {
                            withAnimation(.spring) {
                                store.roleOverride = (store.currentRole == .instructor) ? .student : .instructor
                            }
                        } label: {
                            Label("Act as \(store.currentRole == .instructor ? "Student" : "Instructor")", systemImage: "person.leftright")
                        }
                        
                        Button {
                            withAnimation(.snappy) {
                                store.isFullscreen.toggle()
                            }
                        } label: {
                            Label(store.isFullscreen ? "Exit Fullscreen" : "Enter Fullscreen", systemImage: store.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                DatePicker("Class starts", selection: $score.startTime, displayedComponents: .hourAndMinute).labelsHidden()
                    
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "tablecells.fill.badge.plus")
                            .foregroundStyle(.cyan)
                        TextField("Google Sheet CSV URL", text: $csvURLString)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Import CSV") {
                            guard let url = URL(string: csvURLString) else { return }
                            Task {
                                do {
                                    try await store.importFromCSV(url: url)
                                    csvURLString = ""
                                } catch {
                                    store.errorMessage = "Failed to import CSV: \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack(spacing: 10) {
                        Button("Open in Keynote (Current State)", systemImage: "play.desktopcomputer") {
                            Task { await store.createLiveKeynote(themeName: "Basic Black") }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        
                        Button("Choose Theme...", systemImage: "paintbrush") {
                            showKeynoteThemePicker = true
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Sync from Keynote", systemImage: "arrow.triangle.2.circlepath") {
                            store.pullFromKeynote()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Import as New Week", systemImage: "plus.rectangle.on.folder") {
                            store.importKeynoteAsNewScore()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Export Deck File", systemImage: "macwindow.and.cursorarrow") {
                            exportHTMLSlideshow()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Copy CSV", systemImage: "doc.on.doc") {
                            let csv = store.exportToCSV()
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(csv, forType: .string)
                            #else
                            UIPasteboard.general.string = csv
                            #endif
                            store.errorMessage = "CSV copied to clipboard!"
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Server Settings", systemImage: "network") {
                            showServerConfig = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                ForEach($score.blocks) { $block in
                    ScoreBlockCard(block: $block, start: store.startTime(for: block.id, in: score), isExpanded: expanded.contains(block.id), toggle: {
                        withAnimation(.snappy) { if expanded.contains(block.id) { expanded.remove(block.id) } else { expanded.insert(block.id) } }
                    }, onRecordVideo: { slideID in
                        recordingSlideID = slideID
                    }, onGenerateImage: { slideID in
                        generatingImageForSlideID = slideID
                    }, onExpandProvocation: { slideID in
                        editingProvocationSlideID = slideID
                    })
                }
            }
            .padding(26)
            .frame(maxWidth: 850)
        }
        .background(.clear)
        .sheet(item: Binding(
            get: { recordingSlideID.map { IdentifiableUUID(id: $0) } },
            set: { recordingSlideID = $0?.id }
        )) { wrapper in
            VideoRecorderView { url in
                if let index = score.blocks.firstIndex(where: { block in block.slides.contains(where: { $0.id == wrapper.id }) }) {
                    if let slideIndex = score.blocks[index].slides.firstIndex(where: { $0.id == wrapper.id }) {
                        score.blocks[index].slides[slideIndex].mediaURL = url.absoluteString
                        score.blocks[index].slides[slideIndex].mediaType = .video
                    }
                }
                recordingSlideID = nil
            }
        }
        .sheet(isPresented: $showServerConfig) {
            ServerConfigSheet()
        }
        .sheet(item: Binding(
            get: { generatingImageForSlideID.map { IdentifiableUUID(id: $0) } },
            set: { generatingImageForSlideID = $0?.id }
        )) { wrapper in
            ImageGeneratorSheet(slideID: wrapper.id, score: $score)
        }
        .sheet(item: Binding(
            get: { editingProvocationSlideID.map { IdentifiableUUID(id: $0) } },
            set: { editingProvocationSlideID = $0?.id }
        )) { wrapper in
            ProvocationWorkspaceSheet(slideID: wrapper.id)
        }
        .sheet(isPresented: $showKeynoteThemePicker) {
            KeynoteThemePickerSheet()
        }
    }

    private func exportHTMLSlideshow() {
        #if os(macOS)
        let html = store.exportToHTML(score: score)
        let safeTitle = score.title.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
        let fileName = "Score_Week_\(score.week)_\(safeTitle)_Keynote.html"
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .string)
        
        let possibleDirs = [
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: NSTemporaryDirectory())
        ].compactMap { $0 }
        
        var exportedURL: URL? = nil
        for dir in possibleDirs {
            let targetURL = dir.appendingPathComponent(fileName)
            do {
                try html.write(to: targetURL, atomically: true, encoding: .utf8)
                exportedURL = targetURL
                break
            } catch {
                continue
            }
        }
        
        if let fileURL = exportedURL {
            NSWorkspace.shared.open(fileURL)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            store.errorMessage = "✅ Keynote Deck saved & opened! (\(fileURL.lastPathComponent))"
        } else {
            store.errorMessage = "✅ Keynote Deck HTML copied to Clipboard! Paste into any text editor or browser."
        }
        #endif
    }
}

private struct ScoreBlockCard: View {
    @Environment(ScoreStore.self) private var store
    @Binding var block: ScoreBlock
    let start: Date
    let isExpanded: Bool
    let toggle: () -> Void
    let onRecordVideo: (UUID) -> Void
    let onGenerateImage: (UUID) -> Void
    let onExpandProvocation: (UUID) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(start, format: .dateTime.hour().minute()).font(.headline.monospacedDigit())
                Stepper("\(block.minutes)m", value: $block.minutes, in: 5...240, step: 5).labelsHidden()
                Text("\(block.minutes) MIN").font(.caption2.bold()).foregroundStyle(.secondary)
            }.frame(width: 80)
            RoundedRectangle(cornerRadius: 3).fill(block.phase.color).frame(width: 7).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 8) {
                Button(action: toggle) {
                    HStack {
                        Text(block.phase.label.uppercased()).font(.caption.bold()).foregroundStyle(block.phase.color)
                        Text("thinking with \(block.thinkingWith)").font(.headline)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                Text(block.why).foregroundStyle(.secondary)
                if isExpanded {
                    Divider()
                    EditableDetail(label: "CUE", text: $block.cue)
                    EditableDetail(label: "MEDIUM", text: $block.medium)
                    EditableDetail(label: "ATMOSPHERE", text: $block.atmosphere)
                    Picker("Mode", selection: $block.mode) { ForEach(StudioMode.allCases) { Text($0.label).tag($0) } }
                    
                    Toggle("Continue slide numbering from former block", isOn: Binding(
                        get: { block.continueSlideNumbering ?? false },
                        set: { block.continueSlideNumbering = $0 }
                    ))
                    .font(.caption)
                    .padding(.vertical, 4)

                    Divider()
                    Text("SLIDES (PRESENTATION DECK)").font(.caption.bold()).foregroundStyle(.secondary)

                    if let score = store.scores.first(where: { $0.id == store.selectedScoreID }) {
                        ForEach(Array(block.slides.indices), id: \.self) { idx in
                            let resolvedNum = store.slideNumber(for: block.slides[idx].id, in: score)
                            SlideEditorCard(
                                slide: Binding(
                                    get: { block.slides[idx] },
                                    set: { block.slides[idx] = $0 }
                                ),
                                index: idx,
                                resolvedSlideNumber: resolvedNum,
                                totalSlides: block.slides.count,
                                isActive: store.activeSlideID == block.slides[idx].id,
                                onMoveUp: {
                                    if idx > 0 {
                                        block.slides.swapAt(idx, idx - 1)
                                    }
                                },
                                onMoveDown: {
                                    if idx < block.slides.count - 1 {
                                        block.slides.swapAt(idx, idx + 1)
                                    }
                                },
                                onGoLive: {
                                    store.setActive(scoreID: store.selectedScoreID, blockID: block.id, slideID: block.slides[idx].id)
                                },
                                onDelete: {
                                    block.slides.remove(at: idx)
                                },
                                onDuplicate: {
                                    var copy = block.slides[idx]
                                    copy.id = UUID()
                                    copy.title += " (Copy)"
                                    block.slides.insert(copy, at: idx + 1)
                                },
                                onRecordVideo: {
                                    onRecordVideo(block.slides[idx].id)
                                },
                                onExpandProvocation: {
                                    onExpandProvocation(block.slides[idx].id)
                                }
                            )
                        }
                    }

                    Button(action: {
                        block.slides.append(SlideContent(id: UUID(), title: "New Slide", bodyText: "", mediaType: .none, approvalState: .approved, notes: ""))
                    }) {
                        Label("Add Slide", systemImage: "plus.circle")
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct EditableDetail: View {
    let label: String
    @Binding var text: String
    var body: some View { VStack(alignment: .leading, spacing: 2) { Text(label).font(.caption2.bold()).foregroundStyle(.secondary); TextField(label, text: $text, axis: .vertical).textFieldStyle(.plain) } }
}

struct ServerConfigSheet: View {
    @Environment(ScoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var serverAddress: String = ""
    @State private var pingSuccess: Bool?
    @State private var pinging = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Local-First Sync Server")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Score is a local-first application.")
                    .font(.subheadline.bold())
                Text("Your content (scores, slides, and constitution) is stored securely on this device. To enable class-wide collaboration, run the class server on a local computer and connect to it using its address below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            }
            .padding()
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            
            HStack {
                TextField("Server Address (e.g. http://192.168.1.50:8787)", text: $serverAddress)
                    .textFieldStyle(.roundedBorder)
                
                Button("Test") {
                    testConnection()
                }
                .disabled(serverAddress.isEmpty || pinging)
            }
            
            HStack {
                if pinging {
                    ProgressView().controlSize(.small)
                    Text("Pinging server...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let success = pingSuccess {
                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(success ? .green : .red)
                    Text(success ? "Connected to local server" : "Server unreachable or offline")
                        .font(.caption.bold())
                        .foregroundStyle(success ? .green : .red)
                }
                Spacer()
            }
            
            Button("Save Address") {
                if let url = URL(string: serverAddress) {
                    store.serverURL = url
                    UserDefaults.standard.set(serverAddress, forKey: "serverURL")
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serverAddress.isEmpty)
        }
        .padding(26)
        .frame(width: 480, height: 350)
        .onAppear {
            serverAddress = store.serverURL.absoluteString
        }
    }
    
    private func testConnection() {
        guard let url = URL(string: serverAddress)?.appendingPathComponent("/score/sync") else { return }
        pinging = true
        pingSuccess = nil
        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 3.0
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    pingSuccess = true
                } else {
                    pingSuccess = false
                }
            } catch {
                pingSuccess = false
            }
            pinging = false
        }
    }
}

struct ImageGeneratorSheet: View {
    let slideID: UUID
    @Binding var score: StudioScore
    @Environment(ScoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    
    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Generate Image Asset with AI")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                
                TextField("Describe what you want to generate...", text: $prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
            }
            
            if isGenerating {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Invoking classroom server model to paint asset...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 100)
            } else if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(minHeight: 100)
            } else {
                Spacer().frame(height: 100)
            }
            
            Button("Generate & Apply", systemImage: "sparkles") {
                generate()
            }
            .buttonStyle(.borderedProminent)
            .disabled(prompt.isEmpty || isGenerating)
        }
        .padding(26)
        .frame(width: 480, height: 350)
    }
    
    private func generate() {
        isGenerating = true
        errorMessage = nil
        Task {
            let client = APIClient(baseURL: store.serverURL, token: store.account?.token)
            do {
                let url = try await client.generateImage(prompt: prompt)
                let urlString = url.absoluteString
                
                for index in score.blocks.indices {
                    if let slideIndex = score.blocks[index].slides.firstIndex(where: { $0.id == slideID }) {
                        score.blocks[index].slides[slideIndex].mediaURL = urlString
                        score.blocks[index].slides[slideIndex].mediaType = .image
                        break
                    }
                }
                isGenerating = false
                dismiss()
            } catch {
                isGenerating = false
                errorMessage = "Failed to generate image: \(error.localizedDescription)"
            }
        }
    }
}

struct SlideEditorCard: View {
    @Binding var slide: SlideContent
    let index: Int
    let resolvedSlideNumber: Int
    let totalSlides: Int
    let isActive: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onGoLive: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onRecordVideo: () -> Void
    let onExpandProvocation: () -> Void
    
    @State private var isCollapsed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    withAnimation { isCollapsed.toggle() }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
                
                Image(systemName: "doc.text")
                Text("Slide \(slide.slideNumberOverride ?? resolvedSlideNumber)").font(.caption.bold()).foregroundStyle(.cyan)
                
                HStack(spacing: 4) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up").font(.caption2)
                    }
                    .disabled(index == 0)
                    .buttonStyle(.plain)
                    
                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .disabled(index == totalSlides - 1)
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 4)
                
                TextField("Slide Title", text: $slide.title)
                    .font(.headline)
                    .textFieldStyle(.plain)
                
                Spacer()
                
                Button(action: onDuplicate) {
                    Image(systemName: "square.on.square")
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
                .help("Duplicate Slide")

                Button(action: onGoLive) {
                    Label("Go Live", systemImage: "play.circle.fill")
                        .foregroundStyle(isActive ? .green : .secondary)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            
            if !isCollapsed {
                Picker("Slide Type", selection: Binding(
                    get: { slide.slideLabel ?? .content },
                    set: { slide.slideLabel = $0 }
                )) {
                    ForEach(SlideLabel.allCases) { label in
                        Text(label.label).tag(label)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Content text (markdown supported)", text: $slide.bodyText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                
                TextField("Artwork Attribution (e.g. Artist: Sasha Stiles)", text: Binding(
                    get: { slide.attribution ?? "" },
                    set: { slide.attribution = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Text("Slide Number Override:").font(.caption).foregroundStyle(.secondary)
                    TextField("Auto (\(resolvedSlideNumber))", value: Binding(
                        get: { slide.slideNumberOverride },
                        set: { slide.slideNumberOverride = $0 }
                    ), format: .number)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    
                    if slide.slideNumberOverride != nil {
                        Button("Reset") {
                            slide.slideNumberOverride = nil
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }

                mediaItemsSection
                
                TextField("Presenter Notes (Notes for Nathaniel)", text: $slide.notes, axis: .vertical)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)

                provocationSection
                
                VStack(spacing: 8) {
                    HStack {
                        Text("Approval State:").font(.caption2.bold()).foregroundStyle(.secondary)
                        Picker("Approval", selection: $slide.approvalState) {
                            ForEach(ApprovalState.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    
                    HStack {
                        Text("Template:").font(.caption2.bold()).foregroundStyle(.secondary)
                        Picker("Template", selection: Binding(
                            get: { slide.template ?? .standard },
                            set: { slide.template = $0 }
                        )) {
                            ForEach(SlideTemplate.allCases) { template in
                                Text(template.label).tag(template)
                            }
                        }
                        
                        Spacer()
                        
                        Text("Layout:").font(.caption2.bold()).foregroundStyle(.secondary)
                        Picker("Layout", selection: Binding(
                            get: { slide.layout ?? .standard },
                            set: { slide.layout = $0 }
                        )) {
                            ForEach(SlideLayout.allCases) { layout in
                                Text(layout.label).tag(layout)
                            }
                        }
                    }
                    
                    Text(layoutHint(for: slide.layout ?? .standard))
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(.cyan)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func layoutHint(for layout: SlideLayout) -> String {
        switch layout {
        case .standard:
            return "Standard Layout: Plain or markdown formatted text."
        case .typographic:
            return "Typographic Hero: Large hero title text with muted backdrop image."
        case .conceptGrid:
            return "Concept Grid / Flow: Items separated by dots (e.g. 'paint • sound • code ➔ intelligence')."
        case .twoColumn:
            return "Two-Column Split: Two sections with headers (e.g. 'STUDIO\\n• ...\\n\\nSEMINAR\\n• ...')."
        case .emojiList:
            return "Visual Rhythm List: Items starting with emojis (e.g. '✨ Wonder\\n🧠 Understand')."
        case .wordCloud:
            return "Word Cloud & Quote: Domain tags followed by pull-quote in double quotes."
        case .questionStack:
            return "Stacked Q&A Grid: Numbered questions (e.g. '1. Q1?\\n2. Q2?')."
        }
    }
    
    private var mediaItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEDIA CAROUSEL & ARTIST CITATIONS").font(.caption2.bold()).foregroundStyle(.secondary)
            
            if let items = slide.mediaItems, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.element.id) { itemIdx, item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("Media URL or Local Path", text: Binding(
                                get: { slide.mediaItems?[itemIdx].url ?? "" },
                                set: { slide.mediaItems?[itemIdx].url = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            
                            Picker("Type", selection: Binding(
                                get: { slide.mediaItems?[itemIdx].type ?? .image },
                                set: { slide.mediaItems?[itemIdx].type = $0 }
                            )) {
                                ForEach(SlideMediaType.allCases.filter { $0 != .none }) { mediaType in
                                    Text(mediaType.label).tag(mediaType)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 100)
                            
                            Button {
                                detectLinkInfo(for: itemIdx)
                            } label: {
                                Image(systemName: "wand.and.stars")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Auto-Detect Metadata from Link")
                            
                            if slide.mediaItems?[itemIdx].type == .video {
                                Button(action: onRecordVideo) {
                                    Image(systemName: "video.badge.plus")
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Button {
                                slide.mediaItems?.remove(at: itemIdx)
                            } label: {
                                Image(systemName: "minus.circle").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Artist Citation & Metadata Fields
                        HStack(spacing: 6) {
                            TextField("Artist Name (e.g. Sasha Stiles)", text: Binding(
                                get: { slide.mediaItems?[itemIdx].artistName ?? "" },
                                set: { slide.mediaItems?[itemIdx].artistName = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            
                            TextField("Artwork Title (e.g. Cursive Binary)", text: Binding(
                                get: { slide.mediaItems?[itemIdx].artworkTitle ?? "" },
                                set: { slide.mediaItems?[itemIdx].artworkTitle = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        }
                        
                        HStack(spacing: 6) {
                            TextField("Concept / Focus (e.g. poetry across human & machine)", text: Binding(
                                get: { slide.mediaItems?[itemIdx].caption ?? "" },
                                set: { slide.mediaItems?[itemIdx].caption = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            
                            TextField("Source Web Link (e.g. sashastiles.com/...)", text: Binding(
                                get: { slide.mediaItems?[itemIdx].sourceURL ?? "" },
                                set: { slide.mediaItems?[itemIdx].sourceURL = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            
            Button(action: {
                if slide.mediaItems == nil {
                    slide.mediaItems = []
                }
                slide.mediaItems?.append(SlideMediaItem(id: UUID(), url: "", type: .image))
            }) {
                Label("Add Carousel Media & Citation", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding(8)
        .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func detectLinkInfo(for idx: Int) {
        guard let item = slide.mediaItems?[idx], let url = URL(string: item.url) else { return }
        let host = url.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        if !host.isEmpty && (slide.mediaItems?[idx].sourceURL ?? "").isEmpty {
            slide.mediaItems?[idx].sourceURL = "https://" + host
        }
    }
    
    private var provocationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIVE PROVOCATION / TWITCH QUESTION").font(.caption2.bold()).foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                TextField("Add a question/provocation (markdown)", text: Binding(
                    get: { slide.liveQuestion ?? "" },
                    set: { slide.liveQuestion = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                
                Button(action: onExpandProvocation) {
                    Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                }
                .buttonStyle(.bordered)
                .help("Expand Workspace Editor")
                
                Button {
                    #if os(macOS)
                    let openPanel = NSOpenPanel()
                    openPanel.allowedContentTypes = [.utf8PlainText, .plainText]
                    openPanel.begin { response in
                        if response == .OK, let fileURL = openPanel.url {
                            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                                slide.liveQuestion = content
                            }
                        }
                    }
                    #endif
                } label: {
                    Label("Import .md", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
            }
            
            HStack {
                Text("Display Timer:").font(.caption2.bold()).foregroundStyle(.secondary)
                Picker("Timer", selection: Binding(
                    get: { slide.liveQuestionDuration ?? 0 },
                    set: { slide.liveQuestionDuration = $0 == 0 ? nil : $0 }
                )) {
                    Text("No Timer").tag(0)
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                    Text("120s").tag(120)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 110)
                
                Spacer()
                
                Text("Slide Timer Limit:").font(.caption2.bold()).foregroundStyle(.secondary)
                Picker("Slide Timer", selection: Binding(
                    get: { slide.timeLimit ?? 0 },
                    set: { slide.timeLimit = $0 == 0 ? nil : $0 }
                )) {
                    Text("No Limit").tag(0)
                    Text("1m").tag(60)
                    Text("2m").tag(120)
                    Text("3m").tag(180)
                    Text("5m").tag(300)
                    Text("10m").tag(600)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 110)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ProvocationWorkspaceSheet: View {
    @Environment(ScoreStore.self) private var store
    let slideID: UUID
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Write or paste your bulleted slide provocation using Markdown:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let found = findSlide(id: slideID) {
                    let binding = Binding(
                        get: { found.slide.liveQuestion ?? "" },
                        set: { newValue in
                            store.scores[found.scoreIdx].blocks[found.blockIdx].slides[found.slideIdx].liveQuestion = newValue.isEmpty ? nil : newValue
                        }
                    )
                    
                    TextEditor(text: binding)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    ContentUnavailableView("Slide not found", systemImage: "questionmark.square.dashed")
                }
            }
            .padding()
            .navigationTitle("Provocation Workspace Canvas")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 550, minHeight: 450)
    }
    
    private struct SlideLocation {
        let scoreIdx: Int
        let blockIdx: Int
        let slideIdx: Int
        let slide: SlideContent
    }
    
    private func findSlide(id: UUID) -> SlideLocation? {
        for (sIdx, score) in store.scores.enumerated() {
            for (bIdx, block) in score.blocks.enumerated() {
                for (slIdx, slide) in block.slides.enumerated() {
                    if slide.id == id {
                        return SlideLocation(scoreIdx: sIdx, blockIdx: bIdx, slideIdx: slIdx, slide: slide)
                    }
                }
            }
        }
        return nil
    }
}

struct KeynoteThemePickerSheet: View {
    @Environment(ScoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedCategory: ThemeCategory = .featured
    @State private var selectedTheme: String = "Black"
    @State private var customThemeName: String = ""
    @State private var isGenerating = false
    
    enum ThemeCategory: String, CaseIterable, Identifiable {
        case featured = "🌟 AIScore Default"
        case basic = "⚪️ Basic & Minimal"
        case dynamic = "🌈 Dynamic"
        case academic = "🎓 Academic & School"
        case editorial = "📜 Editorial & Craft"
        case portfolio = "💼 Portfolio & Art"
        case bold = "⚡️ Bold & Cyber"
        case corporate = "🏢 Briefing & Slate"
        case custom = "💎 Custom Template"
        var id: String { rawValue }
    }
    
    struct ThemeInfo {
        let key: String
        let label: String
        let desc: String
        let category: ThemeCategory
    }
    
    let allThemes: [ThemeInfo] = [
        // AIScore Default / Current State
        ThemeInfo(key: "Basic Black", label: "🖤 AIScore Default Dark", desc: "Current AIScore studio dark theme layout", category: .featured),
        ThemeInfo(key: "Basic White", label: "🤍 AIScore Default Light", desc: "Current AIScore studio light theme layout", category: .featured),
        ThemeInfo(key: "Editorial", label: "📄 Editorial Classic", desc: "Serif typography for literary and design score presentations", category: .featured),
        ThemeInfo(key: "Standard Minimalist", label: "🎨 Minimalist", desc: "Clean fine-line layout with subtle monochrome accents", category: .featured),
        
        // Basic & Minimal
        ThemeInfo(key: "Basic Black", label: "Basic Black", desc: "Clean dark background with high-contrast text", category: .basic),
        ThemeInfo(key: "Basic White", label: "Basic White", desc: "Clean white background with dark typography", category: .basic),
        ThemeInfo(key: "Classic White", label: "Classic White", desc: "Traditional clean white slide layout", category: .basic),
        ThemeInfo(key: "Standard Minimalist", label: "Standard Minimalist", desc: "Minimalist fine lines with subtle accents", category: .basic),
        ThemeInfo(key: "Minimalist Light", label: "Minimalist Light", desc: "Light tone minimalist aesthetic", category: .basic),
        ThemeInfo(key: "Minimalist Dark", label: "Minimalist Dark", desc: "Dark tone minimalist aesthetic", category: .basic),
        
        // Dynamic
        ThemeInfo(key: "Dynamic Color", label: "Dynamic Color", desc: "Dynamic color shifts for engaging talks", category: .dynamic),
        ThemeInfo(key: "Dynamic Waves Light", label: "Dynamic Waves Light", desc: "Animated light wave background gradients", category: .dynamic),
        ThemeInfo(key: "Dynamic Waves Dark", label: "Dynamic Waves Dark", desc: "Animated dark wave background gradients", category: .dynamic),
        ThemeInfo(key: "Dynamic Clouds Light", label: "Dynamic Clouds Light", desc: "Soft cloud color motion background", category: .dynamic),
        ThemeInfo(key: "Dynamic Clouds Dark", label: "Dynamic Clouds Dark", desc: "Moody dark cloud motion background", category: .dynamic),
        ThemeInfo(key: "Dynamic Rainbow", label: "Dynamic Rainbow", desc: "Vibrant spectrum motion gradient", category: .dynamic),
        ThemeInfo(key: "Dynamic Chill", label: "Dynamic Chill", desc: "Cool serene color transitions", category: .dynamic),
        
        // Academic & School
        ThemeInfo(key: "Academic Modern", label: "Academic Modern", desc: "Modern layout for research & university lectures", category: .academic),
        ThemeInfo(key: "University Classic", label: "University Classic", desc: "Traditional academic layout with gold accents", category: .academic),
        ThemeInfo(key: "School Simple", label: "School Simple", desc: "Clean layout for course modules & syllabi", category: .academic),
        ThemeInfo(key: "Educator Playful", label: "Educator Playful", desc: "Vibrant engaging layout for active workshops", category: .academic),
        ThemeInfo(key: "Scientific Muted", label: "Scientific Muted", desc: "Muted palette for data sets & scientific diagrams", category: .academic),
        ThemeInfo(key: "Chalkboard", label: "Chalkboard", desc: "Dark chalkboard aesthetic for studio brainstorming", category: .academic),
        ThemeInfo(key: "Academy", label: "Academy", desc: "Formal lecture slide deck template", category: .academic),
        
        // Editorial & Craft
        ThemeInfo(key: "Editorial", label: "Editorial", desc: "Classic magazine serif layout with warm tones", category: .editorial),
        ThemeInfo(key: "Editorial Colorful", label: "Editorial Colorful", desc: "Vibrant editorial accent blocks", category: .editorial),
        ThemeInfo(key: "Journalism Simple", label: "Journalism Simple", desc: "News & publication layout structure", category: .editorial),
        ThemeInfo(key: "Cream Paper", label: "Cream Paper", desc: "Warm textured paper aesthetic", category: .editorial),
        ThemeInfo(key: "Typeset", label: "Typeset", desc: "Emphasis on bold typographic hierarchy", category: .editorial),
        ThemeInfo(key: "Craft", label: "Craft", desc: "Handcrafted studio aesthetic with warm borders", category: .editorial),
        ThemeInfo(key: "Parchment", label: "Parchment", desc: "Historical document & archive aesthetic", category: .editorial),
        
        // Portfolio & Art
        ThemeInfo(key: "Modern Portfolio", label: "Modern Portfolio", desc: "High-contrast frames for visual artwork", category: .portfolio),
        ThemeInfo(key: "Photo Essay", label: "Photo Essay", desc: "Full-bleed imagery & media presentation", category: .portfolio),
        ThemeInfo(key: "Showcase", label: "Showcase", desc: "Gallery wall presentation structure", category: .portfolio),
        ThemeInfo(key: "Look Book", label: "Look Book", desc: "Fashion & design portfolio layout", category: .portfolio),
        ThemeInfo(key: "Exhibition", label: "Exhibition", desc: "Museum & gallery exhibit aesthetic", category: .portfolio),
        ThemeInfo(key: "Photo Portfolio", label: "Photo Portfolio", desc: "Visual photography showcase layout", category: .portfolio),
        ThemeInfo(key: "Artisan", label: "Artisan", desc: "Textured artisan studio deck", category: .portfolio),
        
        // Bold & Cyber
        ThemeInfo(key: "Sales Bold", label: "Sales Bold", desc: "High-energy bold title slides", category: .bold),
        ThemeInfo(key: "Cyber Stark", label: "Cyber Stark", desc: "Dark cybernetic contrast with neon accents", category: .bold),
        ThemeInfo(key: "Purple Tropics", label: "Purple Tropics", desc: "Vibrant violet & neon purple palette", category: .bold),
        ThemeInfo(key: "Bold Color", label: "Bold Color", desc: "High-impact solid color slide backgrounds", category: .bold),
        ThemeInfo(key: "Gradient Colorful", label: "Gradient Colorful", desc: "Multi-color gradient shifts", category: .bold),
        
        // Corporate & Briefing
        ThemeInfo(key: "Briefing", label: "Briefing", desc: "Crisp executive briefing deck layout", category: .corporate),
        ThemeInfo(key: "Slate", label: "Slate", desc: "Refined slate blue executive palette", category: .corporate),
        ThemeInfo(key: "Branding Modern", label: "Branding Modern", desc: "Corporate brand guidelines layout", category: .corporate),
        ThemeInfo(key: "Business Modern", label: "Business Modern", desc: "Modern business presentation layout", category: .corporate),
        ThemeInfo(key: "Startup Simple", label: "Startup Simple", desc: "Clean pitch deck structure for new ideas", category: .corporate)
    ]
    
    var filteredThemes: [ThemeInfo] {
        allThemes.filter { $0.category == selectedCategory }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keynote Theme & Template Gallery")
                        .font(.title3.bold())
                    Text("Select a theme category or enter your custom template name to preview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
            
            Divider()
            
            // Category Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ThemeCategory.allCases) { category in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedCategory = category
                                if category == .custom {
                                    if customThemeName.isEmpty { customThemeName = "MyCustomTheme.kth" }
                                }
                            }
                        } label: {
                            Text(category.rawValue)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedCategory == category ? Color.purple : Color.primary.opacity(0.06), in: Capsule())
                                .foregroundStyle(selectedCategory == category ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            
            Divider()
            
            // Content Area
            if selectedCategory == .custom || !customThemeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Live Real-Time Custom Template Preview Canvas
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Custom / Premium Template Confirmation")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !customThemeName.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Custom Theme Verified")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    
                    // 16:9 Dynamic Custom Theme Canvas
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(colors: [Color(red: 0.1, green: 0.08, blue: 0.16), Color(red: 0.04, green: 0.04, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("CUSTOM KEYNOTE TEMPLATE")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.yellow.opacity(0.25), in: Capsule())
                                    .foregroundStyle(.yellow)
                                
                                Spacer()
                                
                                Text(customThemeName.isEmpty ? "Untitled.kth" : customThemeName)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            
                            Spacer()
                            
                            Text("Thinking With AI")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                            
                            Rectangle()
                                .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                .frame(height: 2)
                            
                            Text("Real-time preview of '\(customThemeName.isEmpty ? "MyCustomTheme.kth" : customThemeName)' for Apple Keynote generation.")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                            
                            Spacer()
                        }
                        .padding(16)
                    }
                    .frame(height: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.yellow.opacity(0.4), lineWidth: 1.5)
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Template File / Name")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        TextField("Type template name (e.g. Luxury Portfolio, Editorial Dark.kth)", text: $customThemeName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxHeight: 340)
            } else {
                // Preset Theme Gallery Grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(filteredThemes, id: \.key) { info in
                            ThemePreviewCard(
                                key: info.key,
                                label: info.label,
                                desc: info.desc,
                                isSelected: selectedTheme == info.key && customThemeName.isEmpty,
                                action: {
                                    selectedTheme = info.key
                                    customThemeName = ""
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 340)
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    let activeName = customThemeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedTheme : customThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text("Selected: \(activeName)")
                        .font(.caption.bold())
                        .foregroundStyle(.purple)
                }
                Spacer()
                Button {
                    isGenerating = true
                    let themeToUse = customThemeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedTheme : customThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        await store.createLiveKeynote(themeName: themeToUse)
                        isGenerating = false
                        dismiss()
                    }
                } label: {
                    if isGenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Generate Presentation in Keynote", systemImage: "play.desktopcomputer")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .padding(24)
        .frame(width: 620, height: 570)
    }
}

struct ThemePreviewCard: View {
    let key: String
    let label: String
    let desc: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    slidePreviewBackground(for: key)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("SLIDE 1")
                                .font(.system(size: 7, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(badgeColor(for: key), in: Capsule())
                                .foregroundStyle(badgeTextColor(for: key))
                            Spacer()
                            Image(systemName: "square.stack")
                                .font(.system(size: 9))
                                .foregroundStyle(secondaryTextColor(for: key))
                        }
                        
                        Text("Thinking With AI")
                            .font(titleFont(for: key))
                            .foregroundStyle(primaryTextColor(for: key))
                            .lineLimit(1)
                        
                        Rectangle()
                            .fill(accentLineColor(for: key))
                            .frame(height: 1.5)
                        
                        Text("A high-fidelity score layout for creative studio practice...")
                            .font(.system(size: 7))
                            .foregroundStyle(secondaryTextColor(for: key))
                            .lineLimit(2)
                    }
                    .padding(10)
                }
                .frame(height: 95)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.purple : Color.white.opacity(0.15), lineWidth: isSelected ? 2.5 : 1)
                )
                
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.purple)
                            .font(.subheadline)
                    }
                }
            }
            .padding(10)
            .background(isSelected ? Color.purple.opacity(0.1) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func slidePreviewBackground(for key: String) -> some View {
        switch key {
        case "Black", "Onyx Pro":
            Color(red: 0.08, green: 0.08, blue: 0.11)
        case "Editorial", "Academic Paper", "Art Monograph":
            Color(red: 0.97, green: 0.95, blue: 0.92)
        case "Minimalist", "Monochrome Minimal":
            Color.white
        case "Classic", "Slate Executive", "Navy Grid":
            LinearGradient(colors: [Color(red: 0.08, green: 0.15, blue: 0.25), Color(red: 0.04, green: 0.08, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Chalkboard":
            Color(red: 0.12, green: 0.18, blue: 0.15)
        case "Modern Portfolio", "Photo Essay", "Gallery Showcase":
            LinearGradient(colors: [Color(red: 0.15, green: 0.15, blue: 0.18), Color(red: 0.05, green: 0.05, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Bold", "Neon Cyber", "Vibrant Gradient", "Typographic":
            LinearGradient(colors: [Color(red: 0.20, green: 0.05, blue: 0.35), Color(red: 0.05, green: 0.10, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            Color(red: 0.96, green: 0.97, blue: 0.98)
        }
    }
    
    private func primaryTextColor(for key: String) -> Color {
        switch key {
        case "Black", "Bold", "Classic", "Slate Executive", "Navy Grid", "Onyx Pro", "Neon Cyber", "Vibrant Gradient", "Typographic", "Chalkboard", "Modern Portfolio", "Photo Essay", "Gallery Showcase": return .white
        case "Editorial", "Academic Paper", "Art Monograph": return Color(red: 0.2, green: 0.18, blue: 0.15)
        default: return .black
        }
    }
    
    private func secondaryTextColor(for key: String) -> Color {
        switch key {
        case "Black", "Bold", "Classic", "Slate Executive", "Navy Grid", "Onyx Pro", "Neon Cyber", "Vibrant Gradient", "Typographic", "Chalkboard", "Modern Portfolio", "Photo Essay", "Gallery Showcase": return .white.opacity(0.65)
        case "Editorial", "Academic Paper", "Art Monograph": return Color(red: 0.45, green: 0.40, blue: 0.35)
        default: return .secondary
        }
    }
    
    private func badgeColor(for key: String) -> Color {
        switch key {
        case "Black": return .cyan.opacity(0.25)
        case "Editorial", "Academic Paper": return Color.orange.opacity(0.2)
        case "Minimalist", "Monochrome Minimal": return Color.gray.opacity(0.2)
        case "Bold", "Neon Cyber", "Vibrant Gradient": return Color.pink.opacity(0.3)
        case "Classic", "Slate Executive", "Navy Grid": return Color.yellow.opacity(0.25)
        default: return Color.blue.opacity(0.2)
        }
    }
    
    private func badgeTextColor(for key: String) -> Color {
        switch key {
        case "Black": return .cyan
        case "Editorial", "Academic Paper": return Color.orange
        case "Minimalist", "Monochrome Minimal": return .primary
        case "Bold", "Neon Cyber", "Vibrant Gradient": return .pink
        case "Classic", "Slate Executive", "Navy Grid": return .yellow
        default: return .blue
        }
    }
    
    private func accentLineColor(for key: String) -> Color {
        switch key {
        case "Black": return .cyan
        case "Editorial", "Academic Paper": return Color(red: 0.7, green: 0.4, blue: 0.3)
        case "Minimalist", "Monochrome Minimal": return .gray.opacity(0.3)
        case "Bold", "Neon Cyber", "Vibrant Gradient": return .purple
        case "Classic", "Slate Executive", "Navy Grid": return .yellow
        default: return .blue
        }
    }
    
    private func titleFont(for key: String) -> Font {
        switch key {
        case "Editorial", "Academic Paper", "Art Monograph": return .system(size: 10, weight: .semibold, design: .serif)
        case "Minimalist", "Monochrome Minimal", "Technical Report": return .system(size: 10, weight: .light, design: .monospaced)
        case "Bold", "Neon Cyber", "Typographic": return .system(size: 11, weight: .black, design: .default)
        default: return .system(size: 10, weight: .bold, design: .default)
        }
    }
}



