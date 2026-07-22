import SwiftUI

struct SeasonGuideView: View {
    @Environment(ScoreStore.self) private var store
    @State private var selectedWeekPreview: StudioScore?
    @State private var expandedActID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Season Guide")
                        .font(.system(.largeTitle, design: .serif))
                        .fontWeight(.bold)
                    Text("Explore the four Acts of the semester timeline.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                ForEach(store.constitution.acts) { act in
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if expandedActID == act.id {
                                    expandedActID = nil
                                } else {
                                    expandedActID = act.id
                                }
                            }
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(act.actNumber)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.blue)
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 8) {
                                        Text(act.weeksString)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.secondary)
                                        
                                        Image(systemName: expandedActID == act.id ? "chevron.up" : "chevron.down")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Text(act.title)
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        
                        if expandedActID == act.id {
                            VStack(alignment: .leading, spacing: 14) {
                                if !act.centralQuestion.isEmpty {
                                    Text("Q: \(act.centralQuestion)")
                                        .font(.headline.italic())
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                }
                                
                                Text(act.description)
                                    .font(.body)
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .padding(.horizontal, 4)
                                
                                Divider().padding(.vertical, 4)
                                
                                let weeksInAct = scoresForAct(act)
                                if weeksInAct.isEmpty {
                                    Text("No weeks configured for this Act.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 12)
                                } else {
                                    VStack(spacing: 10) {
                                        ForEach(weeksInAct) { score in
                                            Button(action: { selectedWeekPreview = score }) {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text("WEEK \(score.week)")
                                                            .font(.caption.bold())
                                                            .foregroundStyle(.secondary)
                                                        Text(score.title)
                                                            .font(.body.bold())
                                                            .foregroundStyle(.primary)
                                                    }
                                                    Spacer()
                                                    
                                                    HStack(spacing: 12) {
                                                        if !score.bigQuestion.isEmpty {
                                                            Text(score.bigQuestion)
                                                                .font(.caption2)
                                                                .foregroundStyle(.secondary)
                                                                .lineLimit(1)
                                                                .frame(maxWidth: 180)
                                                        }
                                                        
                                                        Image(systemName: "rectangle.stack.badge.play.fill")
                                                            .foregroundStyle(.blue)
                                                    }
                                                }
                                                .padding(14)
                                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial.opacity(0.1)))
                }
            }
            .padding(28)
            .frame(maxWidth: 850)
        }
        .background(
            LinearGradient(colors: [.purple.opacity(0.08), .indigo.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .sheet(item: $selectedWeekPreview) { score in
            WeekSlidesPreviewSheet(score: score)
        }
        .onAppear {
            if expandedActID == nil {
                expandedActID = store.constitution.acts.first?.id
            }
        }
    }
    
    private func scoresForAct(_ act: CourseAct) -> [StudioScore] {
        let actNum = act.actNumber.uppercased()
        if actNum.contains("I") && !actNum.contains("V") && !actNum.contains("X") {
            return store.scores.filter { $0.week >= 1 && $0.week <= 3 }.sorted(by: { $0.week < $1.week })
        } else if actNum.contains("II") {
            return store.scores.filter { $0.week >= 4 && $0.week <= 7 }.sorted(by: { $0.week < $1.week })
        } else if actNum.contains("III") {
            return store.scores.filter { $0.week >= 8 && $0.week <= 11 }.sorted(by: { $0.week < $1.week })
        } else if actNum.contains("IV") {
            return store.scores.filter { $0.week >= 12 }.sorted(by: { $0.week < $1.week })
        }
        return []
    }
}

struct WeekSlidesPreviewSheet: View {
    let score: StudioScore
    @Environment(ScoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var activeSlideIndex = 0
    @State private var viewMode: ViewMode = .single
    
    enum ViewMode: String, CaseIterable { case single = "Slide View", grid = "All Slides Grid" }
    
    var allSlides: [SlideContent] {
        score.blocks.flatMap { $0.slides }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week \(score.week) Slide Deck")
                        .font(.headline)
                    Text(score.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Picker("Mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                Button {
                    if let firstBlock = score.blocks.first, let firstSlide = firstBlock.slides.first {
                        store.setActive(scoreID: score.id, blockID: firstBlock.id, slideID: firstSlide.id)
                    }
                    dismiss()
                } label: {
                    Label("Go Live", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            
            Divider()
            
            let slides = allSlides
            if slides.isEmpty {
                ContentUnavailableView("No slides in this week", systemImage: "square.slash")
                    .frame(maxHeight: 280)
            } else {
                if viewMode == .grid {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 14) {
                            ForEach(Array(slides.enumerated()), id: \.element.id) { idx, slide in
                                Button {
                                    activeSlideIndex = idx
                                    viewMode = .single
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Slide \(idx + 1)")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.cyan)
                                        Text(slide.title)
                                            .font(.caption.bold())
                                            .lineLimit(2)
                                            .foregroundStyle(.primary)
                                        
                                        if let mediaURL = slide.mediaURL, !mediaURL.isEmpty, let url = resolveURL(mediaURL) {
                                            CachedAsyncImage(url: url) { image in
                                                image.resizable().scaledToFill().frame(height: 90).clipShape(RoundedRectangle(cornerRadius: 8))
                                            } placeholder: {
                                                Color.gray.opacity(0.2).frame(height: 90).clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    VStack(spacing: 16) {
                        let currentSlide = slides[activeSlideIndex]
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(currentSlide.title)
                                    .font(.title2.bold())
                                Spacer()
                                Text("Slide \(activeSlideIndex + 1) of \(slides.count)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.cyan)
                            }
                            
                            if let mediaItems = currentSlide.mediaItems, !mediaItems.isEmpty {
                                MediaCarouselView(items: mediaItems, resolveURL: resolveURL)
                                    .frame(height: 220)
                            } else if let mediaURL = currentSlide.mediaURL, !mediaURL.isEmpty, let url = resolveURL(mediaURL) {
                                CachedAsyncImage(url: url) { image in
                                    image.resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 10))
                                } placeholder: {
                                    ProgressView()
                                }
                            }
                            
                            Text(currentSlide.bodyText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        
                        HStack {
                            Button(action: { activeSlideIndex = max(0, activeSlideIndex - 1) }) {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.title)
                            }
                            .disabled(activeSlideIndex == 0)
                            
                            Spacer()
                            
                            Text("Slide \(activeSlideIndex + 1) of \(slides.count)")
                                .font(.subheadline.bold())
                            
                            Spacer()
                            
                            Button(action: { activeSlideIndex = min(slides.count - 1, activeSlideIndex + 1) }) {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.title)
                            }
                            .disabled(activeSlideIndex == slides.count - 1)
                        }
                    }
                }
            }
        }
        .padding(26)
        .frame(width: 680, height: 540)
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
}
