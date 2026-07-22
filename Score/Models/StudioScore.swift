import Foundation
import SwiftUI

enum Phase: String, Codable, CaseIterable, Identifiable {
    case arrival, wonder, understand, build, make, reflect, bridge
    var id: Self { self }
    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .arrival: .cyan
        case .wonder: .purple
        case .understand: .blue
        case .build: .orange
        case .make: .pink
        case .reflect: .mint
        case .bridge: .indigo
        }
    }
}

enum StudioMode: String, Codable, CaseIterable, Identifiable {
    case discussion, lecture, studio, crit, walk, guest, `break`
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

enum ApprovalState: String, Codable, CaseIterable, Identifiable {
    case pending, approved, declined, flagged
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

enum SlideMediaType: String, Codable, CaseIterable, Identifiable {
    case none, image, video
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

enum SlideLayout: String, Codable, CaseIterable, Identifiable {
    case standard = "Standard Text"
    case typographic = "Typographic Hero"
    case conceptGrid = "Concept Grid / Flow"
    case twoColumn = "Two-Column Split"
    case emojiList = "Visual Rhythm List"
    case wordCloud = "Word Cloud & Quote"
    case questionStack = "Stacked Q&A Grid"
    
    var id: String { rawValue }
    var label: String { rawValue }
}

enum SlideTemplate: String, Codable, CaseIterable, Identifiable {
    case standard = "Standard Minimal"
    case keynoteDark = "Keynote Dark Bold"
    case cyberpunk = "Cyberpunk Monospace"
    case warmPaper = "Canvas Warm Paper"
    
    var id: String { rawValue }
    var label: String { rawValue }
}

enum SlideLabel: String, Codable, CaseIterable, Identifiable {
    case look = "LOOK"
    case discuss = "DISCUSS"
    case experiment = "EXPERIMENT"
    case content = "INFO"
    
    var id: Self { self }
    var label: String { rawValue }
}

struct SlideMediaItem: Codable, Identifiable, Hashable {
    var id: UUID
    var url: String
    var type: SlideMediaType
}

struct SlideContent: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var bodyText: String
    var mediaType: SlideMediaType
    var mediaURL: String?
    var approvalState: ApprovalState
    var notes: String
    var template: SlideTemplate? = .standard
    var layout: SlideLayout? = .standard
    var liveQuestion: String?
    var liveQuestionDuration: Int? // in seconds
    var slideLabel: SlideLabel? = .content
    var attribution: String?
    var timeLimit: Int? // in seconds
    var requiredOutputs: String?
    var mediaItems: [SlideMediaItem]? = []
    var slideNumberOverride: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, title, bodyText, mediaType, mediaURL, approvalState, notes, template, layout, liveQuestion, liveQuestionDuration, slideLabel, attribution, timeLimit, requiredOutputs, mediaItems, slideNumberOverride
    }
    
    init(id: UUID = UUID(), title: String, bodyText: String, mediaType: SlideMediaType, mediaURL: String? = nil, approvalState: ApprovalState, notes: String, template: SlideTemplate? = .standard, liveQuestion: String? = nil, liveQuestionDuration: Int? = nil, slideLabel: SlideLabel? = .content, attribution: String? = nil, timeLimit: Int? = nil, requiredOutputs: String? = nil, mediaItems: [SlideMediaItem]? = [], slideNumberOverride: Int? = nil, layout: SlideLayout? = .standard) {
        self.id = id
        self.title = title
        self.bodyText = bodyText
        self.mediaType = mediaType
        self.mediaURL = mediaURL
        self.approvalState = approvalState
        self.notes = notes
        self.template = template
        self.layout = layout
        self.liveQuestion = liveQuestion
        self.liveQuestionDuration = liveQuestionDuration
        self.slideLabel = slideLabel
        self.attribution = attribution
        self.timeLimit = timeLimit
        self.requiredOutputs = requiredOutputs
        self.mediaItems = mediaItems
        self.slideNumberOverride = slideNumberOverride
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        bodyText = try container.decode(String.self, forKey: .bodyText)
        mediaType = try container.decode(SlideMediaType.self, forKey: .mediaType)
        mediaURL = try container.decodeIfPresent(String.self, forKey: .mediaURL)
        approvalState = try container.decode(ApprovalState.self, forKey: .approvalState)
        notes = try container.decode(String.self, forKey: .notes)
        template = try container.decodeIfPresent(SlideTemplate.self, forKey: .template) ?? .standard
        layout = try container.decodeIfPresent(SlideLayout.self, forKey: .layout) ?? .standard
        liveQuestion = try container.decodeIfPresent(String.self, forKey: .liveQuestion)
        liveQuestionDuration = try container.decodeIfPresent(Int.self, forKey: .liveQuestionDuration)
        slideLabel = try container.decodeIfPresent(SlideLabel.self, forKey: .slideLabel) ?? .content
        attribution = try container.decodeIfPresent(String.self, forKey: .attribution)
        timeLimit = try container.decodeIfPresent(Int.self, forKey: .timeLimit)
        requiredOutputs = try container.decodeIfPresent(String.self, forKey: .requiredOutputs)
        slideNumberOverride = try container.decodeIfPresent(Int.self, forKey: .slideNumberOverride)
        
        if let items = try container.decodeIfPresent([SlideMediaItem].self, forKey: .mediaItems) {
            mediaItems = items
        } else if let oldURL = mediaURL, !oldURL.isEmpty {
            var parsedItems: [SlideMediaItem] = []
            let separators = ["|", "\n"]
            var splitURLs: [String] = []
            var matched = false
            
            for sep in separators {
                if oldURL.contains(sep) {
                    splitURLs = oldURL.components(separatedBy: sep)
                    matched = true
                    break
                }
            }
            
            if !matched {
                let pattern = ",(?=https?://)"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let nsRange = NSRange(oldURL.startIndex..<oldURL.endIndex, in: oldURL)
                    let matches = regex.matches(in: oldURL, options: [], range: nsRange)
                    var lastIdx = oldURL.startIndex
                    for m in matches {
                        if let matchRange = Range(m.range, in: oldURL) {
                            let urlPart = String(oldURL[lastIdx..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            splitURLs.append(urlPart)
                            lastIdx = matchRange.upperBound
                        }
                    }
                    let lastPart = String(oldURL[lastIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    splitURLs.append(lastPart)
                } else {
                    splitURLs = [oldURL]
                }
            }
            
            for url in splitURLs where !url.isEmpty {
                parsedItems.append(SlideMediaItem(id: UUID(), url: url, type: mediaType))
            }
            mediaItems = parsedItems
        } else {
            mediaItems = []
        }
    }
}

struct Milestone: Identifiable, Codable, Hashable {
    let id: UUID
    var dateString: String
    var title: String
    var detail: String
    var category: String
}

struct CourseAct: Identifiable, Codable, Hashable {
    let id: UUID
    var actNumber: String
    var title: String
    var weeksString: String
    var centralQuestion: String
    var description: String
}

struct CourseConstitution: Codable, Hashable {
    var philosophyTitle: String
    var philosophyIntro: String
    var philosophyBody: String
    var studioQuestions: [String]
    var acts: [CourseAct]
    var milestones: [Milestone]
    
    static var empty: CourseConstitution {
        CourseConstitution(
            philosophyTitle: "Humans have always become more human by thinking-with technologies",
            philosophyIntro: "That proposition sits at the heart of this course.",
            philosophyBody: "From fire to language, writing to photography, printing to the internet, every major technology has changed not only what humans can do, but how humans think, perceive, remember, create, and imagine.",
            studioQuestions: [
                "What is meaning?",
                "What is authorship?",
                "What is representation?",
                "What is memory?",
                "What is agency?",
                "What futures are we building?"
            ],
            acts: [
                CourseAct(id: UUID(), actNumber: "ACT I", title: "Thinking-with", weeksString: "Weeks 1–3", centralQuestion: "How have humans always become more human by thinking-with technologies?", description: "Language, dialogue, intelligence, authorship, manifestos."),
                CourseAct(id: UUID(), actNumber: "ACT II", title: "Seeing-with", weeksString: "Weeks 4–7", centralQuestion: "How do machines learn to see, and how does that change the ways we make images?", description: "Images, diffusion, training, video, public exhibition."),
                CourseAct(id: UUID(), actNumber: "ACT III", title: "Remembering-with", weeksString: "Weeks 8–11", centralQuestion: "Where does memory live?", description: "Embeddings, archives, datasets, training, and AI infrastructures."),
                CourseAct(id: UUID(), actNumber: "ACT IV", title: "Becoming-with", weeksString: "Weeks 12–15", centralQuestion: "What kinds of futures are we building together?", description: "Energy, labor, ecology, post-AI futures, final projects.")
            ],
            milestones: [
                Milestone(id: UUID(), dateString: "Early semester", title: "Charlotte Kent", detail: "Thinking-with; tentative", category: "Guests"),
                Milestone(id: UUID(), dateString: "Mid-semester critique", title: "Charlotte Kent", detail: "Zoom or in person; tentative", category: "Guests"),
                Milestone(id: UUID(), dateString: "Nov. 16 (Mon)", title: "Gallery installation", detail: "Exhibition prep", category: "Exhibition"),
                Milestone(id: UUID(), dateString: "Nov. 18 (Wed)", title: "Exhibition walkthrough / opening", detail: "Opening show", category: "Exhibition"),
                Milestone(id: UUID(), dateString: "Nov. 20 (Fri)", title: "Required Gallery Walkabout", detail: "Walkabout inspection", category: "Exhibition"),
                Milestone(id: UUID(), dateString: "Nov. 11 (Wed)", title: "Nathaniel away", detail: "Independent production day", category: "Special Schedule"),
                Milestone(id: UUID(), dateString: "Nov. 23 (Mon)", title: "No class", detail: "Exhibition reflection assignment", category: "Special Schedule"),
                Milestone(id: UUID(), dateString: "Nov. 25–29", title: "Thanksgiving Recess", detail: "Recess", category: "Special Schedule"),
                Milestone(id: UUID(), dateString: "Dec. 16 (Wed)", title: "Final Critique + Potluck", detail: "Potluck closing", category: "Special Schedule")
            ]
        )
    }
}

struct StudioScore: Identifiable, Codable, Hashable {
    let id: UUID
    var week: Int
    var title: String
    var bigQuestion: String
    var startTime: Date
    var blocks: [ScoreBlock]
}

struct ScoreBlock: Identifiable, Codable, Hashable {
    let id: UUID
    var minutes: Int
    var phase: Phase
    var thinkingWith: String
    var why: String
    var mode: StudioMode
    var medium: String
    var cue: String
    var atmosphere: String
    var slides: [SlideContent]
    var continueSlideNumbering: Bool? = false

    enum CodingKeys: String, CodingKey {
        case id, minutes, phase, thinkingWith, why, mode, medium, cue, atmosphere, slides, continueSlideNumbering
    }

    init(id: UUID = UUID(), minutes: Int, phase: Phase, thinkingWith: String, why: String, mode: StudioMode, medium: String, cue: String, atmosphere: String, slides: [SlideContent] = [], continueSlideNumbering: Bool? = false) {
        self.id = id
        self.minutes = minutes
        self.phase = phase
        self.thinkingWith = thinkingWith
        self.why = why
        self.mode = mode
        self.medium = medium
        self.cue = cue
        self.atmosphere = atmosphere
        self.slides = slides
        self.continueSlideNumbering = continueSlideNumbering
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        minutes = try container.decode(Int.self, forKey: .minutes)
        phase = try container.decode(Phase.self, forKey: .phase)
        thinkingWith = try container.decode(String.self, forKey: .thinkingWith)
        why = try container.decode(String.self, forKey: .why)
        mode = try container.decode(StudioMode.self, forKey: .mode)
        medium = try container.decode(String.self, forKey: .medium)
        cue = try container.decode(String.self, forKey: .cue)
        atmosphere = try container.decode(String.self, forKey: .atmosphere)
        slides = try container.decodeIfPresent([SlideContent].self, forKey: .slides) ?? []
        continueSlideNumbering = try container.decodeIfPresent(Bool.self, forKey: .continueSlideNumbering) ?? false
    }
}

struct StudentPulse: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var response: String
    var createdAt: Date
}

extension StudioScore {
    static var sample: StudioScore {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: .now) ?? .now
        return StudioScore(id: UUID(), week: 1, title: "Week 1 — Thinking With", bigQuestion: "What changes when AI becomes material rather than tool?", startTime: start, blocks: [
            ScoreBlock(id: UUID(), minutes: 15, phase: .arrival, thinkingWith: "music + coffee", why: "Cross the threshold into shared attention.", mode: .discussion, medium: "Ambient stage", cue: "Arrive. Notice what the room is already thinking with.", atmosphere: "Warm, unhurried, curious", slides: [
                SlideContent(id: UUID(), title: "Walk-in", bodyText: "Play Sasha Stiles video as students arrive.", mediaType: .video, mediaURL: "https://example.com/sasha-stiles.mp4", approvalState: .approved, notes: "Ensure audio levels are warm and unhurried.")
            ]),
            ScoreBlock(id: UUID(), minutes: 25, phase: .wonder, thinkingWith: "each other", why: "Make assumptions visible before explaining.", mode: .walk, medium: "Prompt cards", cue: "Pair up. Find a question that makes your partner pause.", atmosphere: "Mobile and speculative", slides: [
                SlideContent(id: UUID(), title: "Cursive Binary", bodyText: "Full-screen image only.", mediaType: .image, mediaURL: "https://example.com/cursive-binary.jpg", approvalState: .approved, notes: "Ask:\n- What do you see?\n- What is this?\n- Is it handwriting? Code? Poetry?\n- Why might someone merge these languages?\nSpend 3–5 minutes in discussion before explaining anything. Artist: Sasha Stiles"),
                SlideContent(
                    id: UUID(),
                    title: "Slide 4 — Language ➔ Images ➔ Memory ➔ Futures",
                    bodyText: "This is not a class about artificial intelligence. It's a class about what happens to creativity when intelligence becomes a material.\n\nIt teaches students to become artists with, against, and beyond AI.",
                    mediaType: .image,
                    mediaURL: "https://refikanadol.com/wp-content/uploads/2021/12/Unsupervised-%E2%80%93-Machine-Hallucination-Moma-x-Refik-Anadol-Studio_Page_10-2400x1350.jpg",
                    approvalState: .approved,
                    notes: "Typographic framing slide. Let the four-word arc 'Language → Images → Memory → Futures' carry it with muted Refik Anadol background.",
                    template: .standard,
                    liveQuestion: nil,
                    liveQuestionDuration: nil,
                    slideLabel: .content,
                    attribution: nil,
                    timeLimit: nil,
                    requiredOutputs: nil,
                    mediaItems: [
                        SlideMediaItem(id: UUID(), url: "https://refikanadol.com/wp-content/uploads/2021/12/Unsupervised-%E2%80%93-Machine-Hallucination-Moma-x-Refik-Anadol-Studio_Page_10-2400x1350.jpg", type: .image)
                    ],
                    slideNumberOverride: 4,
                    layout: .typographic
                ),
                SlideContent(
                    id: UUID(),
                    title: "Slide 5 — Intelligence as a Material",
                    bodyText: "paint • sound • code • clay • cameras ➔ INTELLIGENCE\n\nIf paint, sound, code, clay, and cameras can be artistic materials, what would it mean for intelligence to become one?",
                    mediaType: .none,
                    mediaURL: nil,
                    approvalState: .approved,
                    notes: "DISCUSS: Turn to someone next to you for 2 minutes. What does it mean when intelligence itself becomes a pliable material?",
                    template: .standard,
                    liveQuestion: nil,
                    liveQuestionDuration: nil,
                    slideLabel: .discuss,
                    attribution: nil,
                    timeLimit: nil,
                    requiredOutputs: nil,
                    mediaItems: [],
                    slideNumberOverride: 5,
                    layout: .conceptGrid
                ),
                SlideContent(
                    id: UUID(),
                    title: "Slide 6 — Course Framing",
                    bodyText: "STUDIO\n• We will make things every week\n• Technical skill serves artistic questions\n\nSEMINAR\n• We will read, discuss, and critique\n• Artists, engineers, and humanists bring different expertise",
                    mediaType: .none,
                    mediaURL: nil,
                    approvalState: .approved,
                    notes: "Clarify that no one is expected to arrive already knowing all the tools.",
                    template: .standard,
                    liveQuestion: nil,
                    liveQuestionDuration: nil,
                    slideLabel: .content,
                    attribution: nil,
                    timeLimit: nil,
                    requiredOutputs: nil,
                    mediaItems: [],
                    slideNumberOverride: 6,
                    layout: .twoColumn
                ),
                SlideContent(
                    id: UUID(),
                    title: "Slide 7 — Studio Rhythm",
                    bodyText: "✨ Wonder\n🧠 Understand\n🛠 Build\n🎨 Make\n💬 Reflect",
                    mediaType: .none,
                    mediaURL: nil,
                    approvalState: .approved,
                    notes: "Explain that proportions change—some classes are technical workshops, others studio critique.",
                    template: .standard,
                    liveQuestion: nil,
                    liveQuestionDuration: nil,
                    slideLabel: .content,
                    attribution: nil,
                    timeLimit: nil,
                    requiredOutputs: nil,
                    mediaItems: [],
                    slideNumberOverride: 7,
                    layout: .emojiList
                ),
                SlideContent(
                    id: UUID(),
                    title: "Slide 8 — Why This Class Now?",
                    bodyText: "Writing • Search • Image Gen • Music • Video • Coding • Design • Education • Recommendation • Institutional Decisions\n\n“You cannot meaningfully work with, against, or beyond a technology you have decided not to understand.”",
                    mediaType: .none,
                    mediaURL: nil,
                    approvalState: .approved,
                    notes: "Word cloud / list of domains. End with pull-quote as visual anchor.",
                    template: .standard,
                    liveQuestion: nil,
                    liveQuestionDuration: nil,
                    slideLabel: .content,
                    attribution: nil,
                    timeLimit: nil,
                    requiredOutputs: nil,
                    mediaItems: [],
                    slideNumberOverride: 8,
                    layout: .wordCloud
                ),
                SlideContent(
                    id: UUID(),
                    title: "Slide 9 — Three Questions",
                    bodyText: "1. How do these systems work?\n2. What kinds of art become possible?\n3. What kinds of humans do they encourage us to become?",
                    mediaType: .none,
                    mediaURL: nil,
                    approvalState: .approved,
                    notes: "These return throughout the semester. Clarify that Q3 is not decorative.",
                    template: .standard,
                    liveQuestion: nil,
                    liveQuestionDuration: nil,
                    slideLabel: .content,
                    attribution: nil,
                    timeLimit: nil,
                    requiredOutputs: nil,
                    mediaItems: [],
                    slideNumberOverride: 9,
                    layout: .questionStack
                ),
                SlideContent(
                    id: UUID(),
                    title: "Slide 10 — Studio Questions / Course DNA",
                    bodyText: "1. What is meaning?\n2. What is authorship?\n3. What is representation?\n4. What is memory?\n5. What is agency?\n6. What futures are we building?",
                    mediaType: .none,
                    mediaURL: nil,
                    approvalState: .approved,
                    notes: "Tell students they will not answer these once—questions evolve with technical understanding.",
                    template: .standard,
                    liveQuestion: nil,
                    liveQuestionDuration: nil,
                    slideLabel: .content,
                    attribution: nil,
                    timeLimit: nil,
                    requiredOutputs: nil,
                    mediaItems: [],
                    slideNumberOverride: 10,
                    layout: .questionStack
                ),
                SlideContent(
                    id: UUID(),
                    title: "Slide 11 — Artists We'll Encounter (Artist Constellation)",
                    bodyText: "Visual constellation of artists bridging AI, poetry, machine vision, and archives:\n\n• Sasha Stiles — Cursive Binary / Technelegy\n• Holly Herndon & Mat Dryhurst — The Call / Holly+\n• Anna Ridler — Mosaic Virus\n• Trevor Paglen — Adversarially Evolved Hallucinations\n• Refik Anadol — Unsupervised\n• Jake Elwes — The Zizi Project",
                    mediaType: .image,
                    mediaURL: "https://static.wixstatic.com/media/39587f_fb9e4ca059ed4b16ad9b2f27911309da~mv2.jpg",
                    approvalState: .approved,
                    notes: "First strong visual moment. Let the proposition remain slightly strange. One image per artist.",
                    template: .standard,
                    liveQuestion: nil,
                    liveQuestionDuration: nil,
                    slideLabel: .look,
                    attribution: "Sasha Stiles, Holly Herndon, Mat Dryhurst, Anna Ridler, Trevor Paglen, Refik Anadol, Jake Elwes",
                    timeLimit: nil,
                    requiredOutputs: nil,
                    mediaItems: [
                        SlideMediaItem(id: UUID(), url: "https://static.wixstatic.com/media/39587f_fb9e4ca059ed4b16ad9b2f27911309da~mv2.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://d37zoqglehb9o7.cloudfront.net/uploads/2024/08/SerpentineGallery_HHMD03119_B2-2-1780x1001.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://d37zoqglehb9o7.cloudfront.net/uploads/2024/08/SerpentineGallery_HHMD03182_B1-640x480.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://annaridler.com/content/works/mosaic-2019/block_2/0KH-Muc_Flowers-Forever_IMG_4628.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://paglen.studio/wp-content/uploads/2020/06/Paglen-Comet_2017.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://refikanadol.com/wp-content/uploads/2021/12/Unsupervised-%E2%80%93-Machine-Hallucination-Moma-x-Refik-Anadol-Studio_Page_10-2400x1350.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://www.jakeelwes.com/images/project-zizi19/render.jpeg", type: .image)
                    ],
                    slideNumberOverride: 11
                ),
                SlideContent(
                    id: UUID(),
                    title: "Slide 12 — Artwork Cues for Ezra",
                    bodyText: "Artist • Suggested Work • What It Introduces\n\n• Sasha Stiles — Cursive Binary / TECHNELEGY (Hybrid human-machine language)\n• Holly Herndon — Spawn or Holly+ (Voice, identity, training, governance)\n• Mat Dryhurst — Holly+ / shared projects (Protocols and cultural infrastructure)\n• Anna Ridler — Mosaic Virus (Artist-made datasets and variation)\n• Trevor Paglen — Adversarially Evolved Hallucinations (Classification and machine vision)\n• Refik Anadol — Unsupervised (Archives, data, spectacle, scale)\n• Jake Elwes — The Zizi Project (Bias, identity, counter-datasets)",
                    mediaType: .image,
                    mediaURL: "https://static.wixstatic.com/media/39587f_fb9e4ca059ed4b16ad9b2f27911309da~mv2.jpg",
                    approvalState: .approved,
                    notes: "Pairs each work with its 'what it introduces' column.",
                    template: .standard,
                    liveQuestion: nil,
                    liveQuestionDuration: nil,
                    slideLabel: .content,
                    attribution: "Artist Constellation Introductions",
                    timeLimit: nil,
                    requiredOutputs: nil,
                    mediaItems: [
                        SlideMediaItem(id: UUID(), url: "https://static.wixstatic.com/media/39587f_fb9e4ca059ed4b16ad9b2f27911309da~mv2.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://d37zoqglehb9o7.cloudfront.net/uploads/2024/08/SerpentineGallery_HHMD03119_B2-2-1780x1001.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://d37zoqglehb9o7.cloudfront.net/uploads/2024/08/SerpentineGallery_HHMD03182_B1-640x480.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://annaridler.com/content/works/mosaic-2019/block_2/0KH-Muc_Flowers-Forever_IMG_4628.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://paglen.studio/wp-content/uploads/2020/06/Paglen-Comet_2017.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://refikanadol.com/wp-content/uploads/2021/12/Unsupervised-%E2%80%93-Machine-Hallucination-Moma-x-Refik-Anadol-Studio_Page_10-2400x1350.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://www.jakeelwes.com/images/project-zizi19/render.jpeg", type: .image)
                    ],
                    slideNumberOverride: 12
                ),
                SlideContent(
                    id: UUID(),
                    title: "Slide 13 — Looking Is Already a Technical Practice",
                    bodyText: "• Which work are you most curious about?\n• Which makes you most skeptical?\n• Which appears to reveal its technology?\n• Which hides it?\n• Which seems to work with AI vs. against it?",
                    mediaType: .image,
                    mediaURL: "https://static.wixstatic.com/media/39587f_fb9e4ca059ed4b16ad9b2f27911309da~mv2.jpg",
                    approvalState: .approved,
                    notes: "Turn-and-talk prompt (3-4 minutes). Reuse thumbnail strip of artist constellation for students to point to specific works.",
                    template: .standard,
                    liveQuestion: "• Which work are you most curious about?\n• Which makes you most skeptical?\n• Which appears to reveal its technology?\n• Which hides it?",
                    liveQuestionDuration: 180,
                    slideLabel: .discuss,
                    attribution: "Artist Constellation",
                    timeLimit: nil,
                    requiredOutputs: nil,
                    mediaItems: [
                        SlideMediaItem(id: UUID(), url: "https://static.wixstatic.com/media/39587f_fb9e4ca059ed4b16ad9b2f27911309da~mv2.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://d37zoqglehb9o7.cloudfront.net/uploads/2024/08/SerpentineGallery_HHMD03119_B2-2-1780x1001.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://d37zoqglehb9o7.cloudfront.net/uploads/2024/08/SerpentineGallery_HHMD03182_B1-640x480.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://annaridler.com/content/works/mosaic-2019/block_2/0KH-Muc_Flowers-Forever_IMG_4628.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://paglen.studio/wp-content/uploads/2020/06/Paglen-Comet_2017.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://refikanadol.com/wp-content/uploads/2021/12/Unsupervised-%E2%80%93-Machine-Hallucination-Moma-x-Refik-Anadol-Studio_Page_10-2400x1350.jpg", type: .image),
                        SlideMediaItem(id: UUID(), url: "https://www.jakeelwes.com/images/project-zizi19/render.jpeg", type: .image)
                    ],
                    slideNumberOverride: 13
                )
            ]),
            ScoreBlock(id: UUID(), minutes: 35, phase: .understand, thinkingWith: "examples", why: "Build a shared vocabulary through artifacts.", mode: .lecture, medium: "Deck 1–5", cue: "Name the move, not just the output.", atmosphere: "Focused, conversational", slides: [
                SlideContent(id: UUID(), title: "Transition to language", bodyText: "Language isn't just something AI uses.\n\nLanguage is the material these systems are built from.", mediaType: .none, approvalState: .approved, notes: "Riff on the four large epochs of language."),
                SlideContent(id: UUID(), title: "Ezra Klein interview", bodyText: "Introduce Holly Herndon and Mat Dryhurst.", mediaType: .none, approvalState: .approved, notes: "Ask students: 'What do they think AI actually is?'"),
                SlideContent(id: UUID(), title: "Play clip", bodyText: "Approximately 3–5 minutes.", mediaType: .video, mediaURL: "https://example.com/ezra-klein-clip.mp4", approvalState: .approved, notes: "Focus on the definition of intelligence as a material."),
                SlideContent(id: UUID(), title: "Discussion", bodyText: "Immediate reactions.\n\nNo lecture yet.\n\nCollect observations.", mediaType: .none, approvalState: .approved, notes: "Collect student pulse observations here."),
                SlideContent(id: UUID(), title: "Prediction vs understanding", bodyText: "LLMs predict tokens.\n\nThey don't understand meaning.\n\nUse autocomplete analogy.", mediaType: .none, approvalState: .approved, notes: "Explain autocomplete analogy."),
                SlideContent(id: UUID(), title: "Culture becomes computation", bodyText: "Models learn statistical relationships from human culture:\n\n- Books\n- Images\n- Music\n- Code\n- Conversation", mediaType: .none, approvalState: .approved, notes: "Discuss implications."),
                SlideContent(id: UUID(), title: "Artists should care because...", bodyText: "- Painting learned pigment.\n- Photography learned cameras.\n- We're learning probability models.\n\nThis class is about artistic craft, not AI expertise.", mediaType: .none, approvalState: .approved, notes: "Contextualize artistic craft."),
                SlideContent(id: UUID(), title: "Transition", bodyText: "We've talked about language.\n\nNow let's watch prediction become visual.", mediaType: .none, approvalState: .approved, notes: "Ready the next slides for image generation."),
                SlideContent(id: UUID(), title: "Diffusion animation", bodyText: "Show denoising process.", mediaType: .video, mediaURL: "https://example.com/denoising.mp4", approvalState: .approved, notes: "Explain prediction from noise. Avoid mathematics."),
                SlideContent(id: UUID(), title: "How diffusion works", bodyText: "Noise ➔ Prediction ➔ Repeated refinement ➔ Image", mediaType: .none, approvalState: .approved, notes: "Stress prediction."),
                SlideContent(id: UUID(), title: "Latent space", bodyText: "Explain relationships instead of storage.\n\nExamples:\n- cat ↔ lion\n- chair ↔ couch", mediaType: .image, mediaURL: "https://example.com/latent-space-map.jpg", approvalState: .approved, notes: "Use visual map.")
            ]),
            ScoreBlock(id: UUID(), minutes: 20, phase: .build, thinkingWith: "tools", why: "Translate concepts into active operations.", mode: .studio, medium: "RunPod / LLM", cue: "Experiment with generation parameters.", atmosphere: "Quiet concentration", slides: [
                SlideContent(id: UUID(), title: "Prompting", bodyText: "Show one prompt evolving over several generations.", mediaType: .none, approvalState: .approved, notes: "Demonstrate iterative refinement."),
                SlideContent(id: UUID(), title: "Prompting is craft", bodyText: "Prompting isn't magic.\n\nArtists:\n- Iterate\n- Curate\n- Edit\n- Combine\n- Reject\n\nPrompting is only one part of making.", mediaType: .none, approvalState: .approved, notes: "Explain artist operations."),
                SlideContent(id: UUID(), title: "Artist examples", bodyText: "Brief examples showing different approaches.", mediaType: .none, approvalState: .approved, notes: "Discuss authorship.")
            ]),
            ScoreBlock(id: UUID(), minutes: 50, phase: .make, thinkingWith: "an AI collaborator", why: "Knowledge becomes durable through making.", mode: .studio, medium: "Score AI + sketchbook", cue: "Make one small thing that changes the question.", atmosphere: "Loud hands, quiet judgment", slides: [
                SlideContent(id: UUID(), title: "Studio exercise", bodyText: "Students generate first image series.\n\nSimple prompt assignment.", mediaType: .none, approvalState: .approved, notes: "Encourage experimentation."),
                SlideContent(id: UUID(), title: "Share", bodyText: "Students pair up.\n\nDiscuss:\n- Favorite\n- Surprise\n- Failure", mediaType: .none, approvalState: .approved, notes: "Discuss favorite, surprise, failure.")
            ]),
            ScoreBlock(id: UUID(), minutes: 20, phase: .reflect, thinkingWith: "the room", why: "Let differences become curriculum.", mode: .crit, medium: "Wall + pulse", cue: "What surprised you, and what will you refuse next time?", atmosphere: "Honest and generous", slides: [
                SlideContent(id: UUID(), title: "Reflection", bodyText: "Whole-class discussion.\n\n- What surprised you?\n- What frustrated you?\n- Did AI feel more or less mysterious?", mediaType: .none, approvalState: .approved, notes: "Gather observations on the wall/app pulse."),
                SlideContent(id: UUID(), title: "Assignment", bodyText: "- Readings\n- Set up accounts\n- Generate small image series\n- Bring one success and one failure", mediaType: .none, approvalState: .approved, notes: "Homework details."),
                SlideContent(id: UUID(), title: "Closing", bodyText: "If this isn't a class about artificial intelligence...\n\n...what do you think it's actually a class about?", mediaType: .none, approvalState: .approved, notes: "Leave them with that question.")
            ])
        ])
    }
}

