import Foundation
import Observation
#if os(macOS)
import AppKit
#endif

@MainActor @Observable
final class ScoreStore {
    var scores: [StudioScore] = [] { didSet { scheduleSave() } }
    var selectedScoreID: UUID?
    var account: Account? { didSet { saveAccount() } }
    var background = MediaBackground() { didSet { saveBackground() } }
    var pulses: [StudentPulse] = []
    var chat: [ChatMessage] = []
    var isWorking = false
    var errorMessage: String?
    var serverURL: URL {
        get {
            if let raw = UserDefaults.standard.string(forKey: "serverURL"),
               let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
               url.scheme != nil {
                return url
            }
            return URL(string: "http://127.0.0.1:8787")!
        }
        set {
            UserDefaults.standard.set(newValue.absoluteString, forKey: "serverURL")
        }
    }
    var constitution = CourseConstitution.empty { didSet { saveConstitution() } }

    var activeScoreID: UUID?
    var activeBlockID: UUID?
    var activeSlideID: UUID?
    private var syncTimer: Task<Void, Never>?
    
    var roleOverride: AccountRole? = nil
    var currentRole: AccountRole? {
        roleOverride ?? account?.role
    }

    var isFullscreen: Bool = false
    var showQuestion: Bool = false

    var activeSlide: SlideContent? {
        guard let scoreID = activeScoreID,
              let blockID = activeBlockID,
              let slideID = activeSlideID else { return nil }
        return scores.first { $0.id == scoreID }?
            .blocks.first { $0.id == blockID }?
            .slides.first { $0.id == slideID }
    }

    private let persistence = PersistenceService()
    private var saveTask: Task<Void, Never>?

    init() {
        scores = persistence.load([StudioScore].self, from: "scores.json") ?? [.sample]
        account = persistence.load(Account.self, from: "account.json")
        background = persistence.load(MediaBackground.self, from: "background.json") ?? MediaBackground()
        constitution = persistence.load(CourseConstitution.self, from: "constitution.json") ?? .empty
        selectedScoreID = scores.first?.id
        
        activeScoreID = selectedScoreID
        activeBlockID = scores.first?.blocks.first?.id
        activeSlideID = scores.first?.blocks.first?.slides.first?.id
    }

    var selectedIndex: Int? { scores.firstIndex { $0.id == selectedScoreID } }

    func updateSelected(_ mutate: (inout StudioScore) -> Void) {
        guard let index = selectedIndex else { return }
        mutate(&scores[index])
    }

    func startTime(for blockID: UUID, in score: StudioScore) -> Date {
        var date = score.startTime
        for block in score.blocks {
            if block.id == blockID { return date }
            date = Calendar.current.date(byAdding: .minute, value: block.minutes, to: date) ?? date
        }
        return date
    }

    func slideNumber(for slideID: UUID, in score: StudioScore) -> Int {
        var currentAutoIndex = 0
        for block in score.blocks {
            if !(block.continueSlideNumbering ?? false) {
                currentAutoIndex = 0
            }
            for slide in block.slides {
                currentAutoIndex += 1
                if slide.id == slideID {
                    return slide.slideNumberOverride ?? currentAutoIndex
                }
            }
        }
        return 1
    }

    func addWeek() {
        let week = (scores.map(\.week).max() ?? 0) + 1
        var score = StudioScore.sample
        score = StudioScore(id: UUID(), week: week, title: "Week \(week) — Untitled", bigQuestion: "What are we trying to notice?", startTime: score.startTime, blocks: score.blocks.map { block in
            ScoreBlock(id: UUID(), minutes: block.minutes, phase: block.phase, thinkingWith: block.thinkingWith, why: block.why, mode: block.mode, medium: block.medium, cue: block.cue, atmosphere: block.atmosphere)
        })
        scores.append(score)
        selectedScoreID = score.id
    }

    func deleteWeek(id: UUID) {
        scores.removeAll { $0.id == id }
        if selectedScoreID == id {
            selectedScoreID = scores.first?.id
        }
    }

    func signIn(name: String, email: String, role: AccountRole) async {
        isWorking = true; defer { isWorking = false }
        do {
            account = try await APIClient(baseURL: serverURL).signIn(name: name, email: email, role: role)
        } catch {
            account = Account(id: UUID(), name: name, email: email, role: role, token: nil)
            errorMessage = "Offline demo mode: \(error.localizedDescription)"
        }
        startSyncLoop()
    }

    func askAI(_ prompt: String) async {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chat.append(ChatMessage(id: UUID(), role: "user", text: prompt, createdAt: .now))
        isWorking = true; defer { isWorking = false }
        do {
            let score = selectedIndex.map { scores[$0] }
            let reply = try await APIClient(baseURL: serverURL, token: account?.token).chat(prompt: prompt, score: score)
            chat.append(ChatMessage(id: UUID(), role: "assistant", text: reply, createdAt: .now))
        } catch { errorMessage = error.localizedDescription }
    }

    func generateBackground(prompt: String) async {
        isWorking = true; defer { isWorking = false }
        do {
            let url = try await APIClient(baseURL: serverURL, token: account?.token).generateImage(prompt: prompt)
            background = MediaBackground(kind: .image, source: url.absoluteString, prompt: prompt, motion: background.motion)
        } catch { errorMessage = error.localizedDescription }
    }

    func signOut() {
        syncTimer?.cancel()
        account = nil
        chat.removeAll()
        pulses.removeAll()
    }

    func setActive(scoreID: UUID?, blockID: UUID?, slideID: UUID?) {
        self.activeScoreID = scoreID
        self.activeBlockID = blockID
        self.activeSlideID = slideID
        Task { await performSync() }
    }

    func nextSlide() {
        guard let currentScore = scores.first(where: { $0.id == activeScoreID }) ?? scores.first else { return }
        let allSlides = currentScore.blocks.flatMap { $0.slides }
        guard !allSlides.isEmpty else { return }
        if let currentID = activeSlideID, let idx = allSlides.firstIndex(where: { $0.id == currentID }), idx < allSlides.count - 1 {
            let next = allSlides[idx + 1]
            if let block = currentScore.blocks.first(where: { $0.slides.contains(where: { $0.id == next.id }) }) {
                setActive(scoreID: currentScore.id, blockID: block.id, slideID: next.id)
            }
        } else if activeSlideID == nil, let first = allSlides.first {
            if let block = currentScore.blocks.first(where: { $0.slides.contains(where: { $0.id == first.id }) }) {
                setActive(scoreID: currentScore.id, blockID: block.id, slideID: first.id)
            }
        }
    }
    
    func prevSlide() {
        guard let currentScore = scores.first(where: { $0.id == activeScoreID }) ?? scores.first else { return }
        let allSlides = currentScore.blocks.flatMap { $0.slides }
        guard !allSlides.isEmpty else { return }
        if let currentID = activeSlideID, let idx = allSlides.firstIndex(where: { $0.id == currentID }), idx > 0 {
            let prev = allSlides[idx - 1]
            if let block = currentScore.blocks.first(where: { $0.slides.contains(where: { $0.id == prev.id }) }) {
                setActive(scoreID: currentScore.id, blockID: block.id, slideID: prev.id)
            }
        }
    }

    func startSyncLoop() {
        syncTimer?.cancel()
        syncTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self = await self else { break }
                await self.performSync()
            }
        }
    }

    func performSync() async {
        let isPresenter = currentRole == .instructor
        let client = APIClient(baseURL: serverURL, token: account?.token)
        do {
            if isPresenter {
                let state = try await client.postSync(
                    activeScoreID: activeScoreID,
                    activeBlockID: activeBlockID,
                    activeSlideID: activeSlideID,
                    scores: scores,
                    pulses: pulses,
                    constitution: constitution
                )
                if let updatedPulses = state.pulses {
                    self.pulses = updatedPulses
                }
            } else {
                let state = try await client.getSync()
                if let scoreID = state.activeScoreID { self.activeScoreID = scoreID }
                if let blockID = state.activeBlockID { self.activeBlockID = blockID }
                if let slideID = state.activeSlideID { self.activeSlideID = slideID }
                if let updatedScores = state.scores { self.scores = updatedScores }
                if let updatedPulses = state.pulses { self.pulses = updatedPulses }
                if let updatedConstitution = state.constitution { self.constitution = updatedConstitution }
            }
        } catch {
            // Local fallback synchronization on the Mac filesystem when server is offline
            syncLocally(isPresenter: isPresenter)
        }
    }
    
    struct LiveStatePayload: Codable {
        let activeScoreID: UUID?
        let activeBlockID: UUID?
        let activeSlideID: UUID?
        let scores: [StudioScore]?
        let pulses: [StudentPulse]?
        let constitution: CourseConstitution?
    }
    
    private func syncLocally(isPresenter: Bool) {
        let filename = "shared_live_state.json"
        if isPresenter {
            let payload = LiveStatePayload(
                activeScoreID: activeScoreID,
                activeBlockID: activeBlockID,
                activeSlideID: activeSlideID,
                scores: scores,
                pulses: pulses,
                constitution: constitution
            )
            persistence.save(payload, to: filename)
        } else {
            if let payload = persistence.load(LiveStatePayload.self, from: filename) {
                if let scoreID = payload.activeScoreID { self.activeScoreID = scoreID }
                if let blockID = payload.activeBlockID { self.activeBlockID = blockID }
                if let slideID = payload.activeSlideID { self.activeSlideID = slideID }
                if let updatedScores = payload.scores { self.scores = updatedScores }
                if let updatedPulses = payload.pulses { self.pulses = updatedPulses }
                if let updatedConstitution = payload.constitution { self.constitution = updatedConstitution }
            }
        }
    }

    func parseCSV(_ text: String) -> [[String]] {
        var result: [[String]] = []
        let chars = Array(text)
        var idx = 0
        var currentField = ""
        var currentRecord: [String] = []
        var inQuotes = false
        
        while idx < chars.count {
            let char = chars[idx]
            if inQuotes {
                if char == "\"" {
                    if idx + 1 < chars.count && chars[idx + 1] == "\"" {
                        currentField.append("\"")
                        idx += 2
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == "," {
                    currentRecord.append(currentField)
                    currentField = ""
                } else if char == "\r" || char == "\n" {
                    currentRecord.append(currentField)
                    if !currentRecord.allSatisfy({ $0.isEmpty }) || !currentRecord.isEmpty {
                        result.append(currentRecord)
                    }
                    currentRecord = []
                    currentField = ""
                    if char == "\r" && idx + 1 < chars.count && chars[idx + 1] == "\n" {
                        idx += 1
                    }
                } else {
                    currentField.append(char)
                }
            }
            idx += 1
        }
        if !currentField.isEmpty || !currentRecord.isEmpty {
            currentRecord.append(currentField)
            result.append(currentRecord)
        }
        return result
    }

    func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    func exportToCSV() -> String {
        var lines = ["Week,Phase,Minutes,ThinkingWith,Why,Mode,Medium,Cue,Atmosphere,SlideTitle,SlideBody,SlideMediaType,SlideMediaURL,SlideApprovalState,SlideNotes"]
        for score in scores {
            for block in score.blocks {
                if block.slides.isEmpty {
                    let row = [
                        "\(score.week)",
                        block.phase.rawValue,
                        "\(block.minutes)",
                        block.thinkingWith,
                        block.why,
                        block.mode.rawValue,
                        block.medium,
                        block.cue,
                        block.atmosphere,
                        "", "", "", "", "", ""
                    ]
                    lines.append(row.map { escapeCSVField($0) }.joined(separator: ","))
                } else {
                    for slide in block.slides {
                        let row = [
                            "\(score.week)",
                            block.phase.rawValue,
                            "\(block.minutes)",
                            block.thinkingWith,
                            block.why,
                            block.mode.rawValue,
                            block.medium,
                            block.cue,
                            block.atmosphere,
                            slide.title,
                            slide.bodyText,
                            slide.mediaType.rawValue,
                            slide.mediaURL ?? "",
                            slide.approvalState.rawValue,
                            slide.notes
                        ]
                        lines.append(row.map { escapeCSVField($0) }.joined(separator: ","))
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    func importFromCSV(text: String) {
        let rows = parseCSV(text)
        guard rows.count > 1 else { return }
        
        var weekScores: [Int: (title: String, bigQuestion: String, blocks: [UUID: ScoreBlock], blockOrder: [UUID])] = [:]
        
        for row in rows.dropFirst() {
            guard row.count >= 9 else { continue }
            
            let week = Int(row[0]) ?? 1
            let phaseStr = row[1]
            let minutes = Int(row[2]) ?? 15
            let thinkingWith = row[3]
            let why = row[4]
            let modeStr = row[5]
            let medium = row[6]
            let cue = row[7]
            let atmosphere = row[8]
            
            let phase = Phase(rawValue: phaseStr) ?? .understand
            let mode = StudioMode(rawValue: modeStr) ?? .discussion
            
            if weekScores[week] == nil {
                let existing = scores.first { $0.week == week }
                let title = existing?.title ?? "Week \(week)"
                let bigQuestion = existing?.bigQuestion ?? "What are we trying to notice?"
                weekScores[week] = (title: title, bigQuestion: bigQuestion, blocks: [:], blockOrder: [])
            }
            
            let blockKey = "\(phase.rawValue)-\(thinkingWith)-\(cue)"
            var blockID: UUID
            if let existingID = weekScores[week]?.blocks.first(where: { $0.value.phase == phase && $0.value.thinkingWith == thinkingWith && $0.value.cue == cue })?.key {
                blockID = existingID
            } else {
                blockID = UUID()
                let newBlock = ScoreBlock(
                    id: blockID,
                    minutes: minutes,
                    phase: phase,
                    thinkingWith: thinkingWith,
                    why: why,
                    mode: mode,
                    medium: medium,
                    cue: cue,
                    atmosphere: atmosphere,
                    slides: []
                )
                weekScores[week]?.blocks[blockID] = newBlock
                weekScores[week]?.blockOrder.append(blockID)
            }
            
            if row.count >= 15 {
                let slideTitle = row[9]
                let slideBody = row[10]
                let slideMediaStr = row[11]
                let slideMediaURL = row[12].isEmpty ? nil : row[12]
                let slideApprovalStr = row[13]
                let slideNotes = row[14]
                
                if !slideTitle.isEmpty || !slideBody.isEmpty {
                    let mediaType = SlideMediaType(rawValue: slideMediaStr) ?? .none
                    let approvalState = ApprovalState(rawValue: slideApprovalStr) ?? .pending
                    let slide = SlideContent(
                        id: UUID(),
                        title: slideTitle,
                        bodyText: slideBody,
                        mediaType: mediaType,
                        mediaURL: slideMediaURL,
                        approvalState: approvalState,
                        notes: slideNotes
                    )
                    weekScores[week]?.blocks[blockID]?.slides.append(slide)
                }
            }
        }
        
        var newScores: [StudioScore] = []
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: .now) ?? .now
        
        for (week, data) in weekScores.sorted(by: { $0.key < $1.key }) {
            let orderedBlocks = data.blockOrder.compactMap { data.blocks[$0] }
            let score = StudioScore(
                id: scores.first { $0.week == week }?.id ?? UUID(),
                week: week,
                title: data.title,
                bigQuestion: data.bigQuestion,
                startTime: scores.first { $0.week == week }?.startTime ?? start,
                blocks: orderedBlocks
            )
            newScores.append(score)
        }
        
        if !newScores.isEmpty {
            self.scores = newScores
            self.selectedScoreID = newScores.first?.id
        }
    }

    func importFromCSV(url: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        importFromCSV(text: text)
    }

    func importFromGoogleDoc(url: URL) async throws {
        var targetURL = url
        if url.absoluteString.contains("/document/d/") && url.absoluteString.contains("/edit") {
            let base = url.absoluteString.replacingOccurrences(of: "/edit", with: "/export")
            if let formatted = URL(string: base + "?format=txt") {
                targetURL = formatted
            }
        }
        
        let (data, response) = try await URLSession.shared.data(from: targetURL)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        self.constitution = parseGoogleDocText(text)
        await performSync()
    }
    
    func parseGoogleDocText(_ text: String) -> CourseConstitution {
        var constitution = CourseConstitution.empty
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        var studioQuestions: [String] = []
        var milestones: [Milestone] = []
        var actsMap: [String: CourseAct] = [:]
        
        var currentSection = ""
        var currentCategory = ""
        
        var idx = 0
        while idx < lines.count {
            let line = lines[idx]
            if line.isEmpty {
                idx += 1
                continue
            }
            
            if line.lowercased() == "our studio questions" {
                currentSection = "questions"
                idx += 1
                continue
            } else if line.lowercased() == "the semester" || line.lowercased() == "the four acts" {
                currentSection = "acts"
                idx += 1
                continue
            } else if line.lowercased() == "guests" {
                currentSection = "milestones"
                currentCategory = "Guests"
                idx += 1
                continue
            } else if line.lowercased() == "exhibition" {
                currentSection = "milestones"
                currentCategory = "Exhibition"
                idx += 1
                continue
            } else if line.lowercased() == "special schedule" {
                currentSection = "milestones"
                currentCategory = "Special Schedule"
                idx += 1
                continue
            } else if line.lowercased() == "running threads" {
                currentSection = "milestones"
                currentCategory = "Running Threads"
                idx += 1
                continue
            }
            
            if currentSection == "questions" {
                if line.hasPrefix("●") || line.hasPrefix("-") || line.hasPrefix("*") {
                    let question = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !question.isEmpty {
                        studioQuestions.append(question)
                    }
                } else if !line.isEmpty {
                    currentSection = ""
                }
            } else if currentSection == "acts" {
                if line.uppercased().hasPrefix("ACT ") {
                    let parts = line.components(separatedBy: "—")
                    let actNum = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    var titleAndWeeks = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    var title = titleAndWeeks
                    var weeks = ""
                    
                    if let openParen = titleAndWeeks.firstIndex(of: "("),
                       let closeParen = titleAndWeeks.firstIndex(of: ")") {
                        title = String(titleAndWeeks[..<openParen]).trimmingCharacters(in: .whitespacesAndNewlines)
                        weeks = String(titleAndWeeks[titleAndWeeks.index(after: openParen)..<closeParen]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    
                    var centralQuestion = ""
                    var description = ""
                    
                    idx += 1
                    while idx < lines.count {
                        let nextLine = lines[idx]
                        if nextLine.isEmpty {
                            idx += 1
                            continue
                        }
                        if nextLine.uppercased().hasPrefix("ACT ") || nextLine.lowercased() == "studio rhythm" || nextLine.lowercased() == "season guide" || nextLine.lowercased() == "semester milestones" {
                            idx -= 1
                            break
                        }
                        
                        if nextLine.lowercased().hasPrefix("central question:") {
                            centralQuestion = nextLine.replacingOccurrences(of: "Central Question:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else if description.isEmpty {
                            description = nextLine
                        } else {
                            description += "\n" + nextLine
                        }
                        idx += 1
                    }
                    
                    let actKey = actNum.uppercased()
                    actsMap[actKey] = CourseAct(id: UUID(), actNumber: actNum, title: title, weeksString: weeks, centralQuestion: centralQuestion, description: description)
                }
            } else if currentSection == "milestones" {
                if line.hasPrefix("●") || line.hasPrefix("-") || line.hasPrefix("*") {
                    let milestoneRaw = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                    var dateStr = currentCategory
                    var title = milestoneRaw
                    var detail = ""
                    
                    if let colonIdx = milestoneRaw.firstIndex(of: ":") {
                        dateStr = String(milestoneRaw[..<colonIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                        title = String(milestoneRaw[milestoneRaw.index(after: colonIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let dashIdx = milestoneRaw.range(of: "—") {
                        title = String(milestoneRaw[..<dashIdx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        dateStr = String(milestoneRaw[dashIdx.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    
                    if let parenIdx = title.firstIndex(of: "(") {
                        detail = String(title[parenIdx...]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        title = String(title[..<parenIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    
                    milestones.append(Milestone(id: UUID(), dateString: dateStr, title: title, detail: detail, category: currentCategory))
                }
            }
            idx += 1
        }
        
        if !studioQuestions.isEmpty { constitution.studioQuestions = studioQuestions }
        if !milestones.isEmpty { constitution.milestones = milestones }
        if !actsMap.isEmpty {
            let order = ["ACT I", "ACT II", "ACT III", "ACT IV"]
            var orderedActs: [CourseAct] = []
            for key in order {
                if let matched = actsMap.first(where: { $0.key.contains(key) })?.value {
                    orderedActs.append(matched)
                }
            }
            if !orderedActs.isEmpty { constitution.acts = orderedActs }
        }
        
        var philosophyIntro = ""
        var philosophyBody = ""
        var foundIntro = false
        
        for line in lines {
            if line.isEmpty { continue }
            if line == "Philosophy and DNA" || line == "CRAFTING AI" || line.hasPrefix("Artists, Archives") || line.hasPrefix("Thinking-with Technologies") || line.hasPrefix("Nathaniel Stern") || line.contains("Wisconsin") || line.hasPrefix("Fall 2026") {
                continue
            }
            if line.lowercased() == "our studio questions" || line.lowercased() == "course dna" {
                break
            }
            
            if line.hasPrefix("Humans have always become more human") {
                philosophyIntro = line
                foundIntro = true
                continue
            }
            
            if foundIntro {
                if philosophyBody.isEmpty {
                    philosophyBody = line
                } else {
                    philosophyBody += "\n\n" + line
                }
            }
        }
        
        if !philosophyIntro.isEmpty { constitution.philosophyIntro = philosophyIntro }
        if !philosophyBody.isEmpty { constitution.philosophyBody = philosophyBody }
        
        return constitution
    }
    
    private func saveConstitution() {
        persistence.save(constitution, to: "constitution.json")
    }

    // MARK: - Keynote Direct Automation & Two-Way Sync
    @MainActor
    func createLiveKeynote(themeName: String = "Basic Black") async {
        guard let score = scores.first(where: { $0.id == activeScoreID }) ?? scores.first else { return }
        
        #if os(macOS)
        let success = await KeynoteSyncService.shared.createPresentationInKeynote(score: score, themeName: themeName)
        if success {
            self.errorMessage = "✅ Presentation created live in Apple Keynote!"
        } else {
            self.errorMessage = "⚠️ Could not launch Keynote. Please ensure Keynote is installed."
        }
        #endif
    }
    
    @MainActor
    func pullFromKeynote() {
        guard let activeScoreIndex = scores.firstIndex(where: { $0.id == activeScoreID }) else { return }
        let keynoteSlides = KeynoteSyncService.shared.pullSlidesFromKeynote()
        guard !keynoteSlides.isEmpty else {
            self.errorMessage = "⚠️ No active document open in Keynote. Open your presentation in Keynote first."
            return
        }
        
        var flatSlideRefs: [(blockIndex: Int, slideIndex: Int)] = []
        for bIdx in 0..<scores[activeScoreIndex].blocks.count {
            for sIdx in 0..<scores[activeScoreIndex].blocks[bIdx].slides.count {
                flatSlideRefs.append((bIdx, sIdx))
            }
        }
        
        var updatedCount = 0
        for kSlide in keynoteSlides {
            let targetIdx = kSlide.index - 1
            if targetIdx < flatSlideRefs.count {
                let ref = flatSlideRefs[targetIdx]
                if !kSlide.title.isEmpty {
                    scores[activeScoreIndex].blocks[ref.blockIndex].slides[ref.slideIndex].title = kSlide.title
                }
                if !kSlide.body.isEmpty {
                    scores[activeScoreIndex].blocks[ref.blockIndex].slides[ref.slideIndex].bodyText = kSlide.body
                }
                if !kSlide.notes.isEmpty {
                    scores[activeScoreIndex].blocks[ref.blockIndex].slides[ref.slideIndex].notes = kSlide.notes
                }
                updatedCount += 1
            }
        }
        
        // Safely append any additional slides from Keynote without overwriting existing data
        if keynoteSlides.count > flatSlideRefs.count {
            var newSlides: [SlideContent] = []
            for idx in flatSlideRefs.count..<keynoteSlides.count {
                let kSlide = keynoteSlides[idx]
                let newSlide = SlideContent(
                    title: kSlide.title.isEmpty ? "Slide \(kSlide.index)" : kSlide.title,
                    bodyText: kSlide.body,
                    mediaType: .none,
                    approvalState: .approved,
                    notes: kSlide.notes,
                    slideLabel: .content
                )
                newSlides.append(newSlide)
            }
            if !newSlides.isEmpty {
                let newBlock = ScoreBlock(
                    id: UUID(),
                    minutes: 15,
                    phase: .wonder,
                    thinkingWith: "Keynote Import",
                    why: "Imported Presentation Deck",
                    mode: .lecture,
                    medium: "Keynote Slides",
                    cue: "Keynote Import",
                    atmosphere: "Engaged Studio",
                    slides: newSlides
                )
                scores[activeScoreIndex].blocks.append(newBlock)
            }
        }
        
        scheduleSave()
        self.errorMessage = "🔄 Synced \(keynoteSlides.count) slides from Keynote into AIScore!"
    }
    
    @MainActor
    func importKeynoteAsNewScore() {
        let keynoteSlides = KeynoteSyncService.shared.pullSlidesFromKeynote()
        guard !keynoteSlides.isEmpty else {
            self.errorMessage = "⚠️ No active document open in Keynote. Open your presentation in Keynote first."
            return
        }
        
        let nextWeek = (scores.map { $0.week }.max() ?? 0) + 1
        var importedSlides: [SlideContent] = []
        
        for kSlide in keynoteSlides {
            let slide = SlideContent(
                title: kSlide.title.isEmpty ? "Slide \(kSlide.index)" : kSlide.title,
                bodyText: kSlide.body,
                mediaType: .none,
                approvalState: .approved,
                notes: kSlide.notes,
                slideLabel: .content
            )
            importedSlides.append(slide)
        }
        
        let newBlock = ScoreBlock(
            id: UUID(),
            minutes: 20,
            phase: .wonder,
            thinkingWith: "Keynote Deck",
            why: "Imported Presentation Deck",
            mode: .lecture,
            medium: "Keynote Slides",
            cue: "Keynote Import",
            atmosphere: "Engaged Studio",
            slides: importedSlides
        )
        
        let newScore = StudioScore(
            id: UUID(),
            week: nextWeek,
            title: "Week \(nextWeek) · Keynote Import",
            bigQuestion: "Imported from Keynote Presentation",
            startTime: Date(),
            blocks: [newBlock]
        )
        
        scores.append(newScore)
        activeScoreID = newScore.id
        scheduleSave()
        self.errorMessage = "✨ Imported \(keynoteSlides.count) slides from Keynote as new Week \(nextWeek) deck!"
    }

    func exportToHTML(score: StudioScore) -> String {
        var slidesHTML = ""
        var slideIndex = 0
        for block in score.blocks {
            for slide in block.slides {
                let templateClass = (slide.template ?? .standard).rawValue
                
                var mediaHTML = ""
                if let items = slide.mediaItems, !items.isEmpty {
                    mediaHTML = "<div class='media-gallery'>"
                    for item in items where !item.url.isEmpty {
                        if item.type == .video || item.url.lowercased().hasSuffix(".mp4") || item.url.lowercased().hasSuffix(".mov") {
                            mediaHTML += "<div class='media-container'><video src='\(item.url)' controls></video></div>"
                        } else {
                            mediaHTML += "<div class='media-container'><img src='\(item.url)' alt='Slide Media'/></div>"
                        }
                    }
                    mediaHTML += "</div>"
                } else if let mediaURL = slide.mediaURL, !mediaURL.isEmpty {
                    if mediaURL.lowercased().hasSuffix(".mp4") || mediaURL.lowercased().hasSuffix(".mov") || slide.mediaType == .video {
                        mediaHTML = "<div class='media-container'><video src='\(mediaURL)' controls></video></div>"
                    } else {
                        mediaHTML = "<div class='media-container'><img src='\(mediaURL)' alt='Slide Media'/></div>"
                    }
                }
                
                let labelText = slide.slideLabel?.rawValue ?? "INFO"
                let attributionHTML = (slide.attribution?.isEmpty ?? true) ? "" : "<div class='attribution'>\(slide.attribution!)</div>"
                let outputsHTML = (slide.requiredOutputs?.isEmpty ?? true) ? "" : "<div class='required-outputs'><strong>Required Outputs:</strong> \(slide.requiredOutputs!)</div>"
                let questionHTML = (slide.liveQuestion?.isEmpty ?? true) ? "" : "<div class='live-question'><strong>Provocation:</strong> \(slide.liveQuestion!)</div>"
                let notesHTML = slide.notes.isEmpty ? "" : "<div class='notes'><strong>Presenter Notes:</strong> \(slide.notes)</div>"
                
                var bodyHTML = "<div class='body-text'>\(slide.bodyText.replacingOccurrences(of: "\n", with: "<br/>"))</div>"
                let layoutVal = slide.layout ?? .standard
                if layoutVal == .typographic {
                    bodyHTML = "<div class='body-text typographic-hero'>\(slide.bodyText)</div>"
                } else if layoutVal == .conceptGrid {
                    let parts = slide.bodyText.components(separatedBy: "➔")
                    let inputs = parts.first ?? ""
                    let target = parts.count > 1 ? parts[1] : ""
                    let subparts = target.components(separatedBy: "\n\n")
                    let targetNode = (subparts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let remaining = subparts.dropFirst().joined(separator: "<br/>").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    var gridItemsHTML = ""
                    let materials = inputs.components(separatedBy: "•").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    for mat in materials {
                        gridItemsHTML += "<span class='material-badge'>\(mat)</span>"
                    }
                    
                    bodyHTML = """
                    <div class='concept-flow-container'>
                        <div class='materials-grid'>\(gridItemsHTML)</div>
                        <div class='flow-arrow'>➔</div>
                        <div class='target-node'>\(targetNode.uppercased())</div>
                    </div>
                    """
                    if !remaining.isEmpty {
                        bodyHTML += "<div class='body-text concept-prompt'>\(remaining)</div>"
                    }
                } else if layoutVal == .twoColumn {
                    let blocks = slide.bodyText.components(separatedBy: "\n\n").filter { !$0.isEmpty }
                    var columnsHTML = ""
                    for block in blocks {
                        let lines = block.components(separatedBy: "\n")
                        let title = lines.first ?? ""
                        let bodyLines = lines.dropFirst().map { "<li>\($0)</li>" }.joined()
                        columnsHTML += """
                        <div class='column-card'>
                            <h3>\(title)</h3>
                            <ul>\(bodyLines)</ul>
                        </div>
                        """
                    }
                    bodyHTML = "<div class='two-column-layout'>\(columnsHTML)</div>"
                } else if layoutVal == .emojiList {
                    let items = slide.bodyText.components(separatedBy: "\n").filter { !$0.isEmpty }
                    var listHTML = ""
                    for item in items {
                        let firstChar = String(item.prefix(1))
                        let remaining = String(item.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                        listHTML += """
                        <div class='step-row'>
                            <span class='step-emoji'>\(firstChar)</span>
                            <span class='step-text'>\(remaining)</span>
                        </div>
                        """
                    }
                    bodyHTML = "<div class='step-list-layout'>\(listHTML)</div>"
                } else if layoutVal == .wordCloud {
                    let parts = slide.bodyText.components(separatedBy: "\n\n")
                    let cloudLine = parts.first ?? ""
                    let quoteLine = parts.count > 1 ? parts[1] : ""
                    
                    let tags = cloudLine.components(separatedBy: "•").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    var tagsHTML = ""
                    for tag in tags {
                        tagsHTML += "<span class='cloud-tag'>\(tag)</span>"
                    }
                    var quoteHTML = ""
                    if !quoteLine.isEmpty {
                        quoteHTML = "<div class='quote-card'>\(quoteLine)</div>"
                    }
                    bodyHTML = """
                    <div class='word-cloud-layout'>
                        <div class='tags-container'>\(tagsHTML)</div>
                        \(quoteHTML)
                    </div>
                    """
                } else if layoutVal == .questionStack {
                    let questions = slide.bodyText.components(separatedBy: "\n").filter { !$0.isEmpty }
                    var questionsHTML = ""
                    for q in questions {
                        questionsHTML += """
                        <div class='question-card'>
                            <span class='question-icon'>?</span>
                            <span class='question-body'>\(q)</span>
                        </div>
                        """
                    }
                    bodyHTML = "<div class='question-stack-layout'>\(questionsHTML)</div>"
                }
                
                slidesHTML += """
                <section class="slide \(templateClass) layout-\(layoutVal.rawValue)" id="slide-\(slideIndex)">
                    <div class="slide-content">
                        <div class="meta">
                            <span>WEEK \(score.week) &middot; \(block.phase.label.uppercased())</span>
                            <span class="label-badge label-\(labelText.lowercased())">\(labelText)</span>
                        </div>
                        <h1>\(slide.title)</h1>
                        \(attributionHTML)
                        \(mediaHTML)
                        \(bodyHTML)
                        \(outputsHTML)
                        \(questionHTML)
                        \(notesHTML)
                    </div>
                </section>
                """
                slideIndex += 1
            }
        }
        
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(score.title) - Presentation Deck</title>
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; }
                body {
                    background: #111;
                    color: #fff;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    overflow: hidden;
                    width: 100vw;
                    height: 100vh;
                }
                .slides-container {
                    position: relative;
                    width: 100%;
                    height: 100%;
                }
                .slide {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    opacity: 0;
                    visibility: hidden;
                    transition: opacity 0.5s ease, visibility 0.5s ease;
                    padding: 40px;
                }
                .slide.active {
                    opacity: 1;
                    visibility: visible;
                }
                .slide-content {
                    width: 100%;
                    max-width: 1000px;
                    background: rgba(255, 255, 255, 0.05);
                    border-radius: 24px;
                    padding: 40px;
                    box-shadow: 0 20px 50px rgba(0,0,0,0.3);
                    backdrop-filter: blur(10px);
                    -webkit-backdrop-filter: blur(10px);
                    border: 1px solid rgba(255,255,255,0.1);
                    display: flex;
                    flex-direction: column;
                    gap: 20px;
                    overflow-y: auto;
                    max-height: 90vh;
                }
                .meta {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    font-size: 0.8rem;
                    text-transform: uppercase;
                    letter-spacing: 2px;
                    color: rgba(255,255,255,0.5);
                }
                .label-badge {
                    padding: 4px 8px;
                    border-radius: 4px;
                    font-weight: bold;
                    font-size: 0.75rem;
                }
                .label-look { background: #00d2ff; color: #000; }
                .label-discuss { background: #9b51e0; color: #fff; }
                .label-experiment { background: #ff007f; color: #fff; }
                .label-info { background: rgba(255,255,255,0.15); color: #fff; }
                
                .attribution {
                    font-style: italic;
                    font-size: 0.95rem;
                    color: rgba(255,255,255,0.6);
                    margin-top: -10px;
                }
                
                h1 {
                    font-size: 3rem;
                    font-weight: 800;
                    line-height: 1.2;
                }
                .body-text {
                    font-size: 1.5rem;
                    line-height: 1.6;
                    color: rgba(255,255,255,0.9);
                }
                
                .media-gallery {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 15px;
                    justify-content: center;
                    margin: 10px 0;
                }
                .media-container {
                    flex: 1 1 300px;
                    max-width: 100%;
                    text-align: center;
                }
                .media-container img, .media-container video {
                    max-width: 100%;
                    max-height: 400px;
                    border-radius: 12px;
                    box-shadow: 0 8px 24px rgba(0,0,0,0.5);
                }
                
                .required-outputs {
                    margin-top: 15px;
                    padding: 12px;
                    background: rgba(255, 128, 0, 0.1);
                    border-left: 4px solid #ff8000;
                    border-radius: 4px;
                    font-size: 1.1rem;
                }
                .live-question {
                    margin-top: 15px;
                    padding: 12px;
                    background: rgba(0, 210, 255, 0.1);
                    border-left: 4px solid #00d2ff;
                    border-radius: 4px;
                    font-size: 1.1rem;
                }
                
                .notes {
                    margin-top: 20px;
                    padding: 15px;
                    background: rgba(0,0,0,0.3);
                    border-left: 4px solid #00d2ff;
                    border-radius: 4px;
                    font-size: 1rem;
                    color: rgba(255,255,255,0.7);
                }

                /* Structured Layout CSS Styles */
                .typographic-hero { font-size: 2rem; font-weight: bold; font-style: italic; background: linear-gradient(135deg, #00d2ff, #9b51e0); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
                .concept-flow-container { display: flex; align-items: center; gap: 15px; background: rgba(0,0,0,0.3); padding: 15px; border-radius: 12px; border: 1px solid rgba(0,210,255,0.2); }
                .materials-grid { display: flex; flex-wrap: wrap; gap: 8px; }
                .material-badge { background: rgba(255,255,255,0.1); padding: 6px 12px; border-radius: 20px; font-weight: bold; font-size: 0.9rem; border: 1px solid rgba(0,210,255,0.3); }
                .flow-arrow { font-size: 1.8rem; color: #00ff88; font-weight: bold; }
                .target-node { background: linear-gradient(135deg, #00d2ff, #9b51e0); color: #fff; font-weight: bold; padding: 8px 16px; border-radius: 8px; letter-spacing: 1px; }
                
                .two-column-layout { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; }
                .column-card { background: rgba(255,255,255,0.05); padding: 15px; border-radius: 12px; border: 1px solid rgba(255,255,255,0.1); }
                .column-card h3 { color: #00d2ff; margin-bottom: 10px; font-size: 1.3rem; }
                .column-card ul { padding-left: 20px; color: rgba(255,255,255,0.85); font-size: 1.05rem; }
                
                .step-list-layout { display: flex; flex-direction: column; gap: 10px; }
                .step-row { display: flex; align-items: center; gap: 12px; background: rgba(255,255,255,0.05); padding: 10px 15px; border-radius: 10px; border: 1px solid rgba(0,210,255,0.15); }
                .step-emoji { font-size: 1.5rem; }
                .step-text { font-weight: 600; font-size: 1.1rem; }
                
                .word-cloud-layout { display: flex; flex-direction: column; gap: 15px; }
                .tags-container { display: flex; flex-wrap: wrap; gap: 8px; }
                .cloud-tag { background: rgba(0,210,255,0.15); color: #00d2ff; font-weight: bold; font-size: 0.85rem; padding: 6px 12px; border-radius: 16px; }
                .quote-card { background: rgba(255,255,255,0.05); padding: 15px; border-radius: 12px; border-left: 4px solid #00d2ff; font-style: italic; font-size: 1.2rem; }
                
                .question-stack-layout { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
                .question-card { display: flex; align-items: flex-start; gap: 10px; background: rgba(255,255,255,0.05); padding: 12px; border-radius: 10px; border: 1px solid rgba(0,210,255,0.2); }
                .question-icon { background: #00d2ff; color: #000; font-weight: bold; width: 22px; height: 22px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 0.85rem; flex-shrink: 0; }
                
                .slide.keynoteDark {
                    background: linear-gradient(135deg, #1f242e 0%, #0d0f13 100%);
                }
                .slide.keynoteDark h1 {
                    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
                    font-weight: 900;
                    color: #white;
                }
                
                .slide.cyberpunk {
                    background: #000;
                }
                .slide.cyberpunk .slide-content {
                    background: #000;
                    border: 2px solid #00ff66;
                    box-shadow: 0 0 20px rgba(0, 255, 102, 0.3);
                    border-radius: 12px;
                }
                .slide.cyberpunk h1, .slide.cyberpunk .body-text, .slide.cyberpunk .meta, .slide.cyberpunk .notes {
                    font-family: Courier, Monaco, monospace;
                    color: #00ff66;
                    text-shadow: 0 0 5px rgba(0,255,102,0.5);
                }
                .slide.cyberpunk .notes {
                    border-left-color: #00ff66;
                }
                
                .slide.warmPaper {
                    background: #fbf9f0;
                }
                .slide.warmPaper .slide-content {
                    background: #f6f2e5;
                    border: 1px solid rgba(0,0,0,0.1);
                    color: #1a1a1a;
                    box-shadow: 0 10px 30px rgba(0,0,0,0.05);
                }
                .slide.warmPaper h1 {
                    font-family: Georgia, serif;
                    color: #2c2518;
                }
                .slide.warmPaper .body-text {
                    font-family: Georgia, serif;
                    color: #4a3f2d;
                }
                .slide.warmPaper .meta {
                    color: rgba(0,0,0,0.4);
                }
                .slide.warmPaper .notes {
                    background: rgba(0,0,0,0.03);
                    border-left-color: #d1b894;
                    color: rgba(0,0,0,0.6);
                }
                
                .controls {
                    position: absolute;
                    bottom: 30px;
                    right: 40px;
                    display: flex;
                    gap: 15px;
                    z-index: 100;
                }
                .control-btn {
                    background: rgba(255, 255, 255, 0.1);
                    border: 1px solid rgba(255,255,255,0.2);
                    color: #fff;
                    width: 50px;
                    height: 50px;
                    border-radius: 50%;
                    font-size: 1.5rem;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    backdrop-filter: blur(5px);
                    transition: background 0.3s, transform 0.2s;
                }
                .control-btn:hover {
                    background: rgba(255, 255, 255, 0.25);
                    transform: scale(1.05);
                }
                .progress-bar {
                    position: absolute;
                    bottom: 0;
                    left: 0;
                    height: 6px;
                    background: linear-gradient(90deg, #00d2ff, #9b51e0);
                    width: 0%;
                    transition: width 0.3s ease;
                    z-index: 101;
                }
            </style>
        </head>
        <body>
            <div class="slides-container">
                \(slidesHTML)
            </div>
            
            <div class="controls">
                <button class="control-btn" id="prev-btn">&larr;</button>
                <button class="control-btn" id="next-btn">&rarr;</button>
            </div>
            
            <div class="progress-bar" id="progress"></div>
            
            <script>
                const slides = document.querySelectorAll('.slide');
                const prevBtn = document.getElementById('prev-btn');
                const nextBtn = document.getElementById('next-btn');
                const progress = document.getElementById('progress');
                let currentSlide = 0;
                
                if (slides.length > 0) {
                    showSlide(0);
                }
                
                function showSlide(index) {
                    slides[currentSlide].classList.remove('active');
                    currentSlide = (index + slides.length) % slides.length;
                    slides[currentSlide].classList.add('active');
                    
                    const pct = ((currentSlide + 1) / slides.length) * 100;
                    progress.style.width = pct + '%';
                }
                
                prevBtn.addEventListener('click', () => showSlide(currentSlide - 1));
                nextBtn.addEventListener('click', () => showSlide(currentSlide + 1));
                
                document.addEventListener('keydown', (e) => {
                    if (e.key === 'ArrowRight' || e.key === 'ArrowDown' || e.key === ' ') {
                        showSlide(currentSlide + 1);
                        e.preventDefault();
                    } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
                        showSlide(currentSlide - 1);
                        e.preventDefault();
                    }
                });
            </script>
        </body>
        </html>
        """
        return html
    }

    private func scheduleSave() {
        let snapshot = scores
        saveTask?.cancel()
        saveTask = Task { [persistence] in
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled {
                persistence.save(snapshot, to: "scores.json")
            }
        }
    }
    private func saveAccount() {
        if let account { persistence.save(account, to: "account.json") }
        else { persistence.remove("account.json") }
    }
    private func saveBackground() { persistence.save(background, to: "background.json") }
}

@MainActor
final class KeynoteSyncService: ObservableObject {
    static let shared = KeynoteSyncService()
    
    @Published var isKeynoteRunning: Bool = false
    @Published var activePresentationName: String? = nil
    @Published var isAutoSyncEnabled: Bool = false
    
    private init() {}
    
    private var targetAppNames: [String] {
        return ["Keynote Creator Studio", "Keynote"]
    }
    
    func checkKeynoteStatus() -> Bool {
        #if os(macOS)
        let apps = NSWorkspace.shared.runningApplications
        let running = apps.contains { $0.bundleIdentifier == "com.apple.iWork.Keynote" || targetAppNames.contains($0.localizedName ?? "") }
        self.isKeynoteRunning = running
        return running
        #else
        return false
        #endif
    }
    
    func createPresentationInKeynote(score: StudioScore, themeName: String = "Basic Black") async -> Bool {
        #if os(macOS)
        let cleanTheme = themeName.replacingOccurrences(of: "\"", with: "")
        
        for appName in targetAppNames {
            var scriptSource = """
            tell application "\(appName)"
                activate
                set doc to missing value
                try
                    set doc to make new document with properties {document theme:theme "\(cleanTheme)"}
                on error
                    try
                        set doc to make new document
                    end try
                end try
                
                if doc is not missing value then
                    tell doc
                        try
                            delete slide 1
                        end try
            """
            
            for block in score.blocks {
                for slide in block.slides {
                    let cleanTitle = escapeAppleScriptString(slide.title)
                    let cleanBody = escapeAppleScriptString(slide.bodyText)
                    let cleanNotes = escapeAppleScriptString(slide.notes)
                    let question = escapeAppleScriptString(slide.liveQuestion ?? "")
                    
                    var fullNotes = cleanNotes
                    if !question.isEmpty {
                        fullNotes += "\\n\\n[LIVE PROVOCATION]: " + question
                    }
                    
                    scriptSource += """
                    
                    set currentSlide to missing value
                    try
                        set currentSlide to make new slide at end of slides
                    end try
                    
                    if currentSlide is not missing value then
                        tell currentSlide
                            try
                                set presenter notes to "\(fullNotes)"
                            end try
                            try
                                set textList to object text of every text item
                                if (count of textList) > 0 then
                                    set object text of text item 1 to "\(cleanTitle)"
                                end if
                                if (count of textList) > 1 then
                                    set object text of text item 2 to "\(cleanBody)"
                                end if
                            on error
                                try
                                    set title to "\(cleanTitle)"
                                end try
                                try
                                    set body to "\(cleanBody)"
                                end try
                            end try
                        end tell
                    end if
                    """
                }
            }
            
            scriptSource += """
                    end tell
                    return true
                end if
                return false
            end tell
            """
            
            if executeAppleScript(scriptSource) {
                return true
            }
        }
        return false
        #else
        return false
        #endif
    }
    
    func jumpToSlideInKeynote(slideIndex: Int) {
        #if os(macOS)
        for appName in targetAppNames {
            let script = """
            tell application "\(appName)"
                if (count of documents) > 0 then
                    tell front document
                        if slideIndex <= (count of slides) then
                            show slide \(slideIndex + 1)
                        end if
                    end tell
                end if
            end tell
            """
            if executeAppleScript(script) { break }
        }
        #endif
    }
    
    struct KeynoteSlideData {
        let index: Int
        let title: String
        let body: String
        let notes: String
    }
    
    func pullSlidesFromKeynote() -> [KeynoteSlideData] {
        #if os(macOS)
        for appName in targetAppNames {
            let script = """
            tell application "\(appName)"
                if (count of documents) is 0 then return ""
                set slideData to ""
                tell front document
                    repeat with i from 1 to count of slides
                        set s to slide i
                        set t to ""
                        set b to ""
                        set n to ""
                        
                        try
                            set n to presenter notes of s
                        end try
                        
                        try
                            set textList to object text of every text item of s
                            if (count of textList) > 0 then
                                set t to item 1 of textList
                            end if
                            if (count of textList) > 1 then
                                set b to item 2 of textList
                            end if
                        end try
                        
                        set slideData to slideData & i & "|||" & t & "|||" & b & "|||" & n & "<<<SLIDE_BREAK>>>"
                    end repeat
                end tell
                return slideData
            end tell
            """
            
            if let output = executeAppleScriptWithOutput(script), !output.isEmpty {
                var result: [KeynoteSlideData] = []
                let slideBlocks = output.components(separatedBy: "<<<SLIDE_BREAK>>>")
                for blockStr in slideBlocks where !blockStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let parts = blockStr.components(separatedBy: "|||")
                    if parts.count >= 4, let idx = Int(parts[0]) {
                        result.append(KeynoteSlideData(index: idx, title: parts[1], body: parts[2], notes: parts[3]))
                    }
                }
                if !result.isEmpty {
                    return result
                }
            }
        }
        return []
        #else
        return []
        #endif
    }
    
    private func escapeAppleScriptString(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
    
    private func executeAppleScript(_ source: String) -> Bool {
        #if os(macOS)
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: source) {
            let descriptor = scriptObject.executeAndReturnError(&error)
            if let error {
                print("⚠️ NSAppleScript Error: \(error)")
                let processOutput = runOSAScript(source: source)
                return processOutput != nil
            }
            return descriptor.booleanValue || descriptor.stringValue != nil || error == nil
        }
        #endif
        return false
    }
    
    private func executeAppleScriptWithOutput(_ source: String) -> String? {
        #if os(macOS)
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: source) {
            let descriptor = scriptObject.executeAndReturnError(&error)
            if let error {
                print("⚠️ NSAppleScript Error: \(error)")
                return runOSAScript(source: source)
            }
            let val = descriptor.stringValue ?? ""
            return val.isEmpty ? runOSAScript(source: source) : val
        }
        return runOSAScript(source: source)
        #else
        return nil
        #endif
    }
    
    private func runOSAScript(source: String) -> String? {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                return str.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("⚠️ osascript Process Error: \(error)")
        }
        #endif
        return nil
    }
}
