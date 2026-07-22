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
    @State private var editingProvocationSlideID: UUID? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Score title", text: $score.title).font(.largeTitle.bold()).textFieldStyle(.plain)
                    TextField("Big question", text: $score.bigQuestion, axis: .vertical).font(.title3).textFieldStyle(.plain).foregroundStyle(.secondary)
                    DatePicker("Class starts", selection: $score.startTime, displayedComponents: .hourAndMinute).labelsHidden()
                    
                    HStack(spacing: 12) {
                        Image(systemName: "tablecells.fill.badge.plus")
                        TextField("Google Sheet CSV URL", text: $csvURLString)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Import") {
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
                        
                        Button("Export Clipboard", systemImage: "doc.on.doc") {
                            let csv = store.exportToCSV()
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(csv, forType: .string)
                            #else
                            UIPasteboard.general.string = csv
                            #endif
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Export HTML Slideshow", systemImage: "square.and.arrow.up") {
                            exportHTMLSlideshow()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Server Settings", systemImage: "network") {
                            showServerConfig = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 4)
                }.padding(.bottom, 8)

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
            }.padding(26).frame(maxWidth: 850)
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
    }

    private func exportHTMLSlideshow() {
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.html]
        savePanel.nameFieldStringValue = "\(score.title.replacingOccurrences(of: " ", with: "_"))_presentation.html"
        savePanel.title = "Save HTML Presentation Slide Deck"
        savePanel.message = "Choose where to save your high-fidelity presentation deck."
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let html = store.exportToHTML(score: score)
                do {
                    try html.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    store.errorMessage = "Failed to write HTML presentation: \(error.localizedDescription)"
                }
            }
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
                        block.slides.append(SlideContent(id: UUID(), title: "New Slide", bodyText: "", mediaType: .none, approvalState: .pending, notes: ""))
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
    let onRecordVideo: () -> Void
    let onExpandProvocation: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
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
                .padding(.trailing, 8)
                
                TextField("Slide Title", text: $slide.title)
                    .font(.headline)
                    .textFieldStyle(.plain)
                
                Spacer()
                
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
        VStack(alignment: .leading, spacing: 6) {
            Text("MEDIA CAROUSEL ITEMS").font(.caption2.bold()).foregroundStyle(.secondary)
            
            if let items = slide.mediaItems, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.element.id) { itemIdx, item in
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
                        .frame(width: 90)
                        
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
                }
            }
            
            Button(action: {
                if slide.mediaItems == nil {
                    slide.mediaItems = []
                }
                slide.mediaItems?.append(SlideMediaItem(id: UUID(), url: "", type: .image))
            }) {
                Label("Add Carousel Media Item", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding(8)
        .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
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



