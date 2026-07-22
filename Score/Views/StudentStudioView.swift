import SwiftUI
import AVKit
import WebKit

struct StudentStudioView: View {
    @Environment(ScoreStore.self) private var store
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            if store.isFullscreen {
                StudentLivePresentationView()
                    .transition(.opacity)
            } else {
                TabView(selection: $selectedTab) {
                    StudentLivePresentationView()
                        .tabItem {
                            Label("Live Screen", systemImage: "play.desktopcomputer")
                        }
                        .tag(0)
                    
                    SeasonGuideView()
                        .tabItem {
                            Label("Season Guide", systemImage: "map")
                        }
                        .tag(1)
                        
                    PhilosophyDNAView()
                        .tabItem {
                            Label("Philosophy & DNA", systemImage: "brain.headset")
                        }
                        .tag(2)
                        
                    MilestonesView()
                        .tabItem {
                            Label("Milestones", systemImage: "flag.checkered")
                        }
                        .tag(3)
                }
            }
        }
    }
}

struct StudentLivePresentationView: View {
    @Environment(ScoreStore.self) private var store
    @State private var response = ""
    @State private var sent = false
    
    @State private var questionTimeRemaining = 0
    @State private var activeTimer: Timer? = nil
    @State private var lastLoadedSlideID: UUID? = nil

    var activeScore: StudioScore? {
        store.scores.first { $0.id == store.activeScoreID } ?? store.scores.first
    }
    
    var activeBlock: ScoreBlock? {
        guard let score = activeScore else { return nil }
        return score.blocks.first { $0.id == store.activeBlockID } ?? score.blocks.first
    }
    
    var activeSlide: SlideContent? {
        guard let block = activeBlock else { return nil }
        return block.slides.first { $0.id == store.activeSlideID } ?? block.slides.first
    }
    
    var mediaItemsList: [SlideMediaItem] {
        guard let slide = activeSlide else { return [] }
        if let items = slide.mediaItems, !items.isEmpty {
            return items
        }
        
        guard let mediaURL = slide.mediaURL, !mediaURL.isEmpty else { return [] }
        let type = slide.mediaType
        
        var urls: [String] = []
        let separators = ["|", "\n"]
        var matched = false
        for sep in separators {
            if mediaURL.contains(sep) {
                urls = mediaURL.components(separatedBy: sep)
                matched = true
                break
            }
        }
        if !matched {
            let pattern = ",(?=https?://)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(mediaURL.startIndex..<mediaURL.endIndex, in: mediaURL)
                let matches = regex.matches(in: mediaURL, options: [], range: nsRange)
                var lastIdx = mediaURL.startIndex
                for m in matches {
                    if let matchRange = Range(m.range, in: mediaURL) {
                        let urlPart = String(mediaURL[lastIdx..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        urls.append(urlPart)
                        lastIdx = matchRange.upperBound
                    }
                }
                let lastPart = String(mediaURL[lastIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
                urls.append(lastPart)
            } else {
                urls = [mediaURL]
            }
        }
        return urls.map { SlideMediaItem(id: UUID(), url: $0, type: type) }
    }

    private func resolveURL(_ string: String?) -> URL? {
        guard let string = string, !string.isEmpty else { return nil }
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return URL(string: string)
        }
        if string.hasPrefix("file://") {
            return URL(string: string)
        }
        return URL(fileURLWithPath: string)
    }

    private func headerFont(for template: SlideTemplate) -> Font {
        switch template {
        case .standard: return .largeTitle.bold()
        case .keynoteDark: return .system(size: 38, weight: .black, design: .default)
        case .cyberpunk: return .system(.largeTitle, design: .monospaced).bold()
        case .warmPaper: return .system(.largeTitle, design: .serif).bold()
        }
    }
    
    private func bodyFont(for template: SlideTemplate) -> Font {
        switch template {
        case .standard: return .title3
        case .keynoteDark: return .system(.title3, design: .default).weight(.semibold)
        case .cyberpunk: return .system(.title3, design: .monospaced)
        case .warmPaper: return .system(.title3, design: .serif)
        }
    }
    
    @ViewBuilder
    private func styleSlide<Content: View>(_ slide: SlideContent, @ViewBuilder content: () -> Content) -> some View {
        let template = slide.template ?? .standard
        switch template {
        case .standard:
            content()
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .foregroundStyle(.primary)
        case .keynoteDark:
            content()
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Color(red: 0.1, green: 0.12, blue: 0.16), Color(red: 0.05, green: 0.06, blue: 0.08)], startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .foregroundStyle(.white)
                .shadow(radius: 10)
        case .cyberpunk:
            content()
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.green.opacity(0.8), lineWidth: 2)
                )
                .foregroundStyle(.green)
                .shadow(color: .green.opacity(0.3), radius: 8)
        case .warmPaper:
            content()
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.96, green: 0.94, blue: 0.88))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                .shadow(color: .black.opacity(0.1), radius: 6)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isFullscreen {
                    if let slide = activeSlide {
                        ZStack {
                            // Immersive full-bleed media backgrounds
                            let items = mediaItemsList
                            if !items.isEmpty {
                                FullscreenMediaBackgroundView(items: items, resolveURL: resolveURL)
                                    .ignoresSafeArea()
                            } else {
                                Color.black.ignoresSafeArea()
                            }
                            
                            // overlay title & descriptions on top of full-bleed media content
                            VStack(alignment: .leading, spacing: 0) {
                                Spacer()
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        let resolvedNum = activeScore.map { store.slideNumber(for: slide.id, in: $0) } ?? 1
                                        let slideIndexText = "Slide \(slide.slideNumberOverride ?? resolvedNum)"
                                        Text(slideIndexText)
                                            .font(.caption.bold())
                                            .foregroundStyle(.cyan)
                                        
                                        Spacer()
                                        
                                        slideLabelBadge(for: slide)
                                    }
                                    
                                    Text(slide.title)
                                        .font(.largeTitle.bold())
                                        .foregroundStyle(.white)
                                    
                                    if let att = slide.attribution, !att.isEmpty {
                                        Text(att)
                                            .font(.subheadline)
                                            .italic()
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                    
                                    if slide.approvalState != .approved {
                                        Text("Slide Pending Review")
                                            .font(.headline)
                                            .foregroundStyle(.orange)
                                    } else {
                                        renderSlideContent(for: slide, darkTheme: true)
                                        
                                        requiredOutputsBox(for: slide)
                                    }
                                }
                                .padding(30)
                                .background(
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.65), .black.opacity(0.9)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                            .ignoresSafeArea(edges: .bottom)
                            
                            // Timed provocation popups
                            questionOverlayView(for: slide)
                            
                            // twitch comment feed
                            chatOverlayView
                        }
                    } else {
                        ContentUnavailableView("No active slide", systemImage: "rectangle.dashed")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if let score = activeScore, let block = activeBlock {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("WEEK \(score.week) · \(score.title)").font(.caption.bold()).foregroundStyle(.secondary)
                                    HStack {
                                        Text(block.phase.label.uppercased())
                                            .font(.headline.bold())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(block.phase.color, in: Capsule())
                                        Text("Thinking with \(block.thinkingWith)").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                
                                if let slide = activeSlide {
                                    ZStack(alignment: .bottomLeading) {
                                        styleSlide(slide) {
                                            VStack(alignment: .leading, spacing: 16) {
                                                HStack {
                                                    let resolvedNum = activeScore.map { store.slideNumber(for: slide.id, in: $0) } ?? 1
                                                    let slideIndexText = "Slide \(slide.slideNumberOverride ?? resolvedNum)"
                                                    Text(slideIndexText)
                                                        .font(.caption.bold())
                                                        .foregroundStyle(.cyan)
                                                    Spacer()
                                                    slideLabelBadge(for: slide)
                                                }
                                                
                                                Text(slide.title)
                                                    .font(headerFont(for: slide.template ?? .standard))
                                                
                                                if let att = slide.attribution, !att.isEmpty {
                                                    Text(att)
                                                        .font(.subheadline)
                                                        .italic()
                                                        .foregroundStyle(.secondary)
                                                        .padding(.top, -10)
                                                }
                                                
                                                if slide.approvalState != .approved {
                                                    ContentUnavailableView(
                                                        "Slide Pending Review",
                                                        systemImage: "lock.rectangle.stack",
                                                        description: Text("This slide is currently \(slide.approvalState.rawValue) by the instructor.")
                                                    )
                                                    .padding()
                                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                                                } else {
                                                    let items = mediaItemsList
                                                    if !items.isEmpty {
                                                        MediaCarouselView(items: items, resolveURL: resolveURL)
                                                    }
                                                    
                                                    renderSlideContent(for: slide, darkTheme: false)
                                                        
                                                    requiredOutputsBox(for: slide)
                                                }
                                            }
                                        }
                                        
                                        chatOverlayView
                                        
                                        questionOverlayView(for: slide)
                                    }
                                } else {
                                    ContentUnavailableView("No active slide", systemImage: "rectangle.dashed", description: Text("Waiting for the instructor to start presenting..."))
                                }
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Add your pulse to the room").font(.headline)
                                    TextField("What are you noticing right now?", text: $response, axis: .vertical)
                                        .textFieldStyle(.roundedBorder)
                                        .lineLimit(3...6)
                                    
                                    Button(sent ? "Pulse Shared" : "Share Pulse", systemImage: sent ? "checkmark" : "paperplane.fill") {
                                        store.pulses.append(StudentPulse(id: UUID(), displayName: store.account?.name ?? "Student", response: response, createdAt: .now))
                                        response = ""
                                        sent = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { sent = false }
                                        Task { await store.performSync() }
                                    }.disabled(response.isEmpty)
                                }
                                .padding(20)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                            } else {
                                ContentUnavailableView("No active scores available", systemImage: "tray")
                            }
                        }
                        .padding()
                        .frame(maxWidth: 720)
                    }
                    .background(.clear)
                    .navigationTitle("Score Live Room")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Log out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { store.signOut() }
                        }
                    }
                }
            }
        }
        .onChange(of: store.activeSlideID) { _, newID in
            handleActiveSlideChange(to: newID)
        }
        .onAppear {
            handleActiveSlideChange(to: store.activeSlideID)
        }
    }
    
    @ViewBuilder
    private func slideLabelBadge(for slide: SlideContent) -> some View {
        if let label = slide.slideLabel, label != .content {
            Text(label.rawValue)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(label == .look ? Color.cyan : (label == .discuss ? Color.purple : Color.pink))
                )
        }
    }
    
    @ViewBuilder
    private func requiredOutputsBox(for slide: SlideContent) -> some View {
        if let outputs = slide.requiredOutputs, !outputs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
                    Text("EXPECTED OUTPUT").font(.caption.bold()).foregroundStyle(.orange)
                }
                Text(.init(outputs))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    private func questionOverlayView(for slide: SlideContent) -> some View {
        if store.showQuestion, let question = slide.liveQuestion {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles.rectangle.stack.fill").foregroundStyle(.cyan)
                    Text("STUDIO PROVOCATION").font(.caption2.bold()).foregroundStyle(.cyan)
                    Spacer()
                    if questionTimeRemaining > 0 {
                        Text("\(questionTimeRemaining)s").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Text(.init(question))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.opacity(0.85))
                    .shadow(color: .cyan.opacity(0.3), radius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.cyan.opacity(0.5), lineWidth: 1.5)
            )
            .frame(maxWidth: 320)
            .padding(20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    private var chatOverlayView: some View {
        VStack {
            Spacer()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.pulses.suffix(15)) { pulse in
                            HStack(alignment: .top, spacing: 6) {
                                Text(pulse.displayName)
                                    .font(.caption2.bold())
                                    .foregroundStyle(Color.cyan)
                                Text(pulse.response)
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                            .shadow(radius: 2)
                            .id(pulse.id)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 120)
                .scrollIndicators(.hidden)
                .onChange(of: store.pulses.count) {
                    if let last = store.pulses.last {
                        withAnimation(.spring) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let last = store.pulses.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: 260)
        .padding(16)
        .allowsHitTesting(false)
    }

    private func handleActiveSlideChange(to slideID: UUID?) {
        guard let slide = activeSlide else { return }
        if slideID != lastLoadedSlideID {
            lastLoadedSlideID = slideID
            activeTimer?.invalidate()
            
            if let question = slide.liveQuestion, !question.isEmpty {
                store.showQuestion = true
                if let duration = slide.liveQuestionDuration, duration > 0 {
                    questionTimeRemaining = duration
                    activeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                        Task { @MainActor in
                            if questionTimeRemaining > 1 {
                                questionTimeRemaining -= 1
                            } else {
                                questionTimeRemaining = 0
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    store.showQuestion = false
                                }
                                t.invalidate()
                            }
                        }
                    }
                } else {
                    questionTimeRemaining = 0
                }
            } else {
                store.showQuestion = false
                questionTimeRemaining = 0
            }
        }
    }

    @ViewBuilder
    private func renderSlideContent(for slide: SlideContent, darkTheme: Bool) -> some View {
        let layout = slide.layout ?? .standard
        switch layout {
        case .standard:
            Text(.init(slide.bodyText))
                .font(bodyFont(for: slide.template ?? .standard))
                .padding(.vertical, 8)
                
        case .typographic:
            TypographicHeroSlideView(text: slide.bodyText)
                
        case .conceptGrid:
            ConceptGridSlideView(text: slide.bodyText, darkTheme: darkTheme)
                
        case .twoColumn:
            TwoColumnSlideView(text: slide.bodyText, darkTheme: darkTheme)
                
        case .emojiList:
            VisualRhythmSlideView(text: slide.bodyText, darkTheme: darkTheme)
                
        case .wordCloud:
            WordCloudSlideView(text: slide.bodyText, darkTheme: darkTheme)
                
        case .questionStack:
            QuestionStackSlideView(text: slide.bodyText, darkTheme: darkTheme)
        }
    }
}

// MARK: - High-Fidelity Custom Render Views

struct TypographicHeroSlideView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text)
                .font(.system(size: 32, weight: .bold, design: .serif))
                .lineSpacing(8)
                .italic()
                .foregroundStyle(
                    LinearGradient(colors: [Color.cyan, Color.purple, Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(radius: 2)
        }
        .padding(.vertical, 24)
    }
}

struct ConceptGridSlideView: View {
    @Environment(ScoreStore.self) private var store
    let text: String
    let darkTheme: Bool
    
    @State private var selectedMaterial: String? = nil
    @State private var materialResponse: String = ""
    @State private var sent = false
    
    private var parsedParts: (materials: [String], targetNode: String, remainingPrompt: String) {
        let parts = text.components(separatedBy: "➔")
        let inputsPart = parts.first ?? ""
        let targetPart = parts.count > 1 ? parts[1] : ""
        
        let subparts = targetPart.components(separatedBy: "\n\n")
        let targetNode = (subparts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let remainingPrompt = subparts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        let materials = inputsPart.components(separatedBy: "•").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        return (materials, targetNode, remainingPrompt)
    }
    
    var body: some View {
        let parsed = parsedParts
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                // Inputs pill list
                FlowLayout(spacing: 8) {
                    ForEach(parsed.materials, id: \.self) { mat in
                        materialBadge(for: mat)
                    }
                }
                
                // Converter Arrow
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                
                // Target Node
                if !parsed.targetNode.isEmpty {
                    targetNodeView(parsed.targetNode)
                }
            }
            .padding(14)
            .background(Color.black.opacity(darkTheme ? 0.3 : 0.1), in: RoundedRectangle(cornerRadius: 14))
            
            // Inline response block for selected material
            if let mat = selectedMaterial {
                materialResponseField(for: mat)
            }
            
            if !parsed.remainingPrompt.isEmpty {
                Text(parsed.remainingPrompt)
                    .font(.body)
                    .foregroundStyle(darkTheme ? .white.opacity(0.9) : .primary)
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func materialBadge(for mat: String) -> some View {
        let isSelected = selectedMaterial == mat
        let textColor: Color = isSelected ? .cyan : .white
        let strokeColor: Color = isSelected ? .cyan : .cyan.opacity(0.3)
        let strokeWidth: CGFloat = isSelected ? 2 : 1
        
        Text(mat)
            .font(.caption.bold())
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
            .contentShape(Capsule())
            .onTapGesture {
                selectMaterial(mat)
            }
    }
    
    private func selectMaterial(_ mat: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if selectedMaterial == mat {
                selectedMaterial = nil
            } else {
                selectedMaterial = mat
                materialResponse = ""
            }
        }
    }
    
    @ViewBuilder
    private func targetNodeView(_ node: String) -> some View {
        Text(node.uppercased())
            .font(.headline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .purple.opacity(0.4), radius: 6)
    }
    
    @ViewBuilder
    private func materialResponseField(for mat: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pencil.line").foregroundStyle(.cyan)
                Text("Active Focus: \(mat)").font(.caption.bold()).foregroundStyle(.cyan)
                Spacer()
                Button {
                    withAnimation { selectedMaterial = nil }
                } label: {
                    Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            
            HStack(spacing: 8) {
                TextField("How are you using \(mat) with AI?", text: $materialResponse)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    let formattedText = "[\(mat)] \(materialResponse)"
                    store.pulses.append(StudentPulse(
                        id: UUID(),
                        displayName: store.account?.name ?? "Student",
                        response: formattedText,
                        createdAt: .now
                    ))
                    materialResponse = ""
                    sent = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { sent = false }
                    Task { await store.performSync() }
                } label: {
                    Image(systemName: sent ? "checkmark" : "paperplane.fill")
                        .foregroundStyle(sent ? .green : .cyan)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(materialResponse.isEmpty)
            }
        }
        .padding(12)
        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.2), lineWidth: 1))
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }
}

struct TwoColumnSlideView: View {
    let text: String
    let darkTheme: Bool
    
    private var blocks: [String] {
        text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(blocks, id: \.self) { block in
                columnView(for: block)
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func columnView(for block: String) -> some View {
        let lines = block.components(separatedBy: "\n")
        let title = lines.first ?? ""
        let bodyLines = lines.dropFirst()
        
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(.cyan)
            
            ForEach(Array(bodyLines), id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(darkTheme ? .white.opacity(0.85) : .secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.15), lineWidth: 1))
    }
}

struct VisualRhythmSlideView: View {
    let text: String
    let darkTheme: Bool
    
    private var items: [String] {
        text.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                rowView(for: item)
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func rowView(for item: String) -> some View {
        let firstChar = String(item.prefix(1))
        let remaining = String(item.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        
        HStack(spacing: 12) {
            Text(firstChar)
                .font(.title2)
                .padding(8)
                .background(.cyan.opacity(0.15), in: Circle())
            
            Text(remaining)
                .font(.body.weight(.semibold))
                .foregroundStyle(darkTheme ? .white.opacity(0.9) : .primary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WordCloudSlideView: View {
    let text: String
    let darkTheme: Bool
    
    private var parsedData: (tags: [String], quote: String) {
        let parts = text.components(separatedBy: "\n\n")
        let cloudLine = parts.first ?? ""
        let quoteLine = parts.count > 1 ? parts[1] : ""
        let tags = cloudLine.components(separatedBy: "•").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return (tags, quoteLine)
    }
    
    var body: some View {
        let parsed = parsedData
        VStack(alignment: .leading, spacing: 18) {
            FlowLayout(spacing: 6) {
                ForEach(parsed.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.bold())
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.cyan.opacity(0.1), in: Capsule())
                }
            }
            
            if !parsed.quote.isEmpty {
                Text(parsed.quote)
                    .font(.body.italic())
                    .foregroundStyle(darkTheme ? .white : .primary)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.cyan.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(.vertical, 8)
    }
}

struct QuestionStackSlideView: View {
    let text: String
    let darkTheme: Bool
    
    private var questions: [String] {
        text.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(questions, id: \.self) { q in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.cyan)
                    Text(q)
                        .font(.subheadline.bold())
                        .foregroundStyle(darkTheme ? .white : .primary)
                        .multilineTextAlignment(.leading)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.cyan.opacity(0.2), lineWidth: 1))
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - FlowLayout Helper for Word Cloud / tag lists

struct FlowLayout: Layout {
    var spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? 300
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for size in sizes {
            if currentX + size.width > width {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        height = currentY + lineHeight
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = bounds.width
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        
        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct MediaCarouselView: View {
    let items: [SlideMediaItem]
    let resolveURL: (String) -> URL?
    
    @State private var currentIndex = 0
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if items.indices.contains(currentIndex) {
                    let item = items[currentIndex]
                    ZStack(alignment: .bottomLeading) {
                        if let youtubeEmbed = youtubeEmbedURL(from: item.url) {
                            NativeWebView(url: youtubeEmbed)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if let url = resolveURL(item.url) {
                            if item.type == .webpage || (!item.url.lowercased().hasSuffix(".jpg") && !item.url.lowercased().hasSuffix(".jpeg") && !item.url.lowercased().hasSuffix(".png") && !item.url.lowercased().hasSuffix(".mp4") && !item.url.lowercased().hasSuffix(".mov") && item.url.lowercased().hasPrefix("http")) {
                                NativeWebView(url: url)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else if item.type == .video || item.url.lowercased().hasSuffix(".mp4") || item.url.lowercased().hasSuffix(".mov") {
                                NativeVideoPlayer(url: url)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                        .scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } placeholder: {
                                    ProgressView()
                                }
                            }
                        }
                        
                        if item.artistName != nil || item.artworkTitle != nil || item.sourceURL != nil {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    if let artist = item.artistName {
                                        Text(artist)
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                    if let title = item.artworkTitle {
                                        Text("— \(title)")
                                            .font(.caption)
                                            .italic()
                                            .foregroundStyle(.cyan)
                                    }
                                    Spacer()
                                    if let src = item.sourceURL, let srcURL = URL(string: src) {
                                        Link(destination: srcURL) {
                                            HStack(spacing: 3) {
                                                Image(systemName: "arrow.up.right.square")
                                                Text(srcURL.host() ?? "Source")
                                            }
                                            .font(.caption2.bold())
                                            .foregroundStyle(.cyan)
                                        }
                                    }
                                }
                                if let caption = item.caption {
                                    Text(caption)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                            }
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(8)
                        }
                    }
                }
                
                if items.count > 1 {
                    HStack {
                        Button {
                            withAnimation {
                                currentIndex = (currentIndex - 1 + items.count) % items.count
                            }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                        
                        Spacer()
                        
                        Button {
                            withAnimation {
                                currentIndex = (currentIndex + 1) % items.count
                            }
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                }
            }
            .frame(minHeight: 280, maxHeight: 380)
            
            if items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<items.count, id: \.self) { idx in
                        Circle()
                            .fill(idx == currentIndex ? Color.cyan : Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .onTapGesture {
                                withAnimation { currentIndex = idx }
                            }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

struct FullscreenMediaBackgroundView: View {
    let items: [SlideMediaItem]
    let resolveURL: (String) -> URL?
    
    @State private var currentIndex = 0
    
    var body: some View {
        ZStack {
            if items.indices.contains(currentIndex) {
                let item = items[currentIndex]
                if let youtubeEmbed = youtubeEmbedURL(from: item.url) {
                    NativeWebView(url: youtubeEmbed)
                } else if let url = resolveURL(item.url) {
                    if item.type == .webpage || (!item.url.lowercased().hasSuffix(".jpg") && !item.url.lowercased().hasSuffix(".jpeg") && !item.url.lowercased().hasSuffix(".png") && !item.url.lowercased().hasSuffix(".mp4") && !item.url.lowercased().hasSuffix(".mov") && item.url.lowercased().hasPrefix("http")) {
                        NativeWebView(url: url)
                    } else if item.type == .video || item.url.lowercased().hasSuffix(".mp4") || item.url.lowercased().hasSuffix(".mov") {
                        NativeVideoPlayer(url: url)
                    } else {
                        AsyncImage(url: url) { image in
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView()
                        }
                    }
                }
            }
            
            if items.count > 1 {
                HStack {
                    Button {
                        withAnimation {
                            currentIndex = (currentIndex - 1 + items.count) % items.count
                        }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 40)
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            currentIndex = (currentIndex + 1) % items.count
                        }
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 40)
                }
            }
        }
    }
}

// ABI Safe Native Player View to prevent _AVKit_SwiftUI reflection aborts
struct NativeVideoPlayer: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = AVPlayer(url: url)
        playerView.controlsStyle = .floating
        playerView.showsFrameSteppingButtons = false
        playerView.showsSharingServiceButton = false
        playerView.showsFullScreenToggleButton = true
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if let currentPlayer = nsView.player {
            let currentAsset = currentPlayer.currentItem?.asset as? AVURLAsset
            if currentAsset?.url != url {
                nsView.player = AVPlayer(url: url)
            }
        } else {
            nsView.player = AVPlayer(url: url)
        }
    }
}

// WKWebView wrapper for playing embedded YouTube/web videos
struct NativeWebView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        
        loadContent(in: webView)
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if let currentURL = nsView.url, currentURL.absoluteString == url.absoluteString {
            return
        }
        loadContent(in: nsView)
    }
    
    private func loadContent(in webView: WKWebView) {
        if let youtubeID = extractYouTubeID(from: url) {
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
            <style>
              * { box-sizing: border-box; }
              body { margin: 0; padding: 0; background: #000; display: flex; justify-content: center; align-items: center; height: 100vh; width: 100vw; overflow: hidden; }
              iframe { width: 100%; height: 100%; border: none; }
            </style>
            </head>
            <body>
              <iframe src="https://www.youtube.com/embed/\(youtubeID)?autoplay=1&mute=0&controls=1&enablejsapi=1&origin=https://www.youtube.com" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        } else {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    private func extractYouTubeID(from url: URL) -> String? {
        let host = url.host() ?? ""
        if host.contains("youtube.com") {
            if url.pathComponents.contains("embed"), let last = url.pathComponents.last {
                return last
            }
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
               let queryItems = components.queryItems,
               let videoID = queryItems.first(where: { $0.name == "v" })?.value {
                return videoID
            }
        } else if host.contains("youtu.be") {
            return url.lastPathComponent
        }
        return nil
    }
}

// Utility to parse YouTube URLs into clean embed links
func youtubeEmbedURL(from urlString: String) -> URL? {
    guard let url = URL(string: urlString) else { return nil }
    let host = url.host() ?? ""
    if host.contains("youtube.com") {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
           let queryItems = components.queryItems,
           let videoID = queryItems.first(where: { $0.name == "v" })?.value {
            return URL(string: "https://www.youtube.com/embed/\(videoID)")
        }
    } else if host.contains("youtu.be") {
        let videoID = url.lastPathComponent
        return URL(string: "https://www.youtube.com/embed/\(videoID)")
    }
    return nil
}
