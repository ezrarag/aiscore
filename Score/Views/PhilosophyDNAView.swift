import SwiftUI

struct PhilosophyDNAView: View {
    @Environment(ScoreStore.self) private var store
    @State private var docURL = "https://docs.google.com/document/d/1CbABbbFFouMFUuzpBLG9ykDhaXkRjJPwZBr2Ws_HQSk/edit?usp=sharing"
    @State private var isSyncing = false
    @State private var syncError: String?
    
    // AI Provocation State
    @State private var selectedQuestion: String?
    @State private var aiProvocation: String?
    @State private var isGenerating = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header & Google Doc Sync for Educators
                if store.currentRole == .instructor {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Google Doc URL", text: $docURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            
                            Button(action: syncDoc) {
                                if isSyncing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Sync Doc", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSyncing || docURL.isEmpty)
                        }
                        
                        if let error = syncError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("The constitution parses live from your Google Drive document.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                
                // Philosophy Statement
                VStack(alignment: .leading, spacing: 14) {
                    Text(store.constitution.philosophyTitle)
                        .font(.system(.title, design: .serif))
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Text(store.constitution.philosophyIntro)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                    
                    Text(store.constitution.philosophyBody)
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundStyle(.primary.opacity(0.9))
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                
                // Interactive Studio Questions
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                        Text("Interactive DNA: Studio Questions")
                            .font(.title2.bold())
                    }
                    
                    Text("Select a question to dynamically generate an AI provocation for today's studio work.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                        ForEach(store.constitution.studioQuestions, id: \.self) { question in
                            Button(action: { selectQuestion(question) }) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "questionmark.circle.fill")
                                            .foregroundStyle(.blue)
                                        Spacer()
                                        Image(systemName: "arrow.up.right.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Text(question)
                                        .font(.headline)
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(.primary)
                                        .frame(maxHeight: .infinity, alignment: .topLeading)
                                }
                                .padding(16)
                                .frame(height: 120, alignment: .leading)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 850)
        }
        .background(
            ZStack {
                LinearGradient(colors: [.indigo.opacity(0.15), .purple.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .sheet(item: Binding(
            get: { selectedQuestion.map { IdentifiableString(value: $0) } },
            set: { selectedQuestion = $0?.value }
        )) { questionObj in
            provocationSheet(question: questionObj.value)
        }
    }
    
    @ViewBuilder
    private func provocationSheet(question: String) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("Studio Provocation")
                    .font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark.circle.fill") {
                    selectedQuestion = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            
            Text(question)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            
            Divider()
            
            if isGenerating {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Generatively thinking-with AI...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 120)
            } else if let provocation = aiProvocation {
                ScrollView {
                    Text(provocation)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .frame(maxHeight: 250)
            }
            
            Button("Regenerate Prompt", systemImage: "sparkles") {
                generateProvocation(for: question)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)
        }
        .padding(26)
        .frame(width: 480, height: 420)
        .presentationDetents([.medium])
        .onAppear {
            if aiProvocation == nil {
                generateProvocation(for: question)
            }
        }
    }
    
    private func syncDoc() {
        guard let url = URL(string: docURL) else { return }
        isSyncing = true
        syncError = nil
        Task {
            do {
                try await store.importFromGoogleDoc(url: url)
                isSyncing = false
            } catch {
                isSyncing = false
                syncError = "Failed to fetch document: \(error.localizedDescription)"
            }
        }
    }
    
    private func selectQuestion(_ question: String) {
        aiProvocation = nil
        selectedQuestion = question
    }
    
    private func generateProvocation(for question: String) {
        isGenerating = true
        aiProvocation = nil
        Task {
            let prompt = "Based on our course question: '\(question)', generate a short, 2-line poetic provocation or creative studio prompt for students to think-with today."
            let client = APIClient(baseURL: store.serverURL, token: store.account?.token)
            do {
                let response = try await client.chat(prompt: prompt, score: nil)
                aiProvocation = response
                isGenerating = false
            } catch {
                aiProvocation = "Poetry is in the machine, but networking has stalled: \(error.localizedDescription)"
                isGenerating = false
            }
        }
    }
}

struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}
