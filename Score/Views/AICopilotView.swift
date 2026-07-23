import SwiftUI

struct AICopilotView: View {
    @Environment(ScoreStore.self) private var store
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack { Label("Studio copilot", systemImage: "sparkles").font(.headline); Spacer() }.padding()
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if store.chat.isEmpty {
                            Text("Ask for provocations, alternate rhythms, critique prompts, or a rewritten block. The current score is included as context.")
                                .foregroundStyle(.secondary).padding()
                        }
                        ForEach(store.chat) { message in
                            Text(message.text).padding(12)
                                .background(message.role == "user" ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading).id(message.id)
                        }
                    }.padding()
                }.onChange(of: store.chat.count) { _, _ in if let id = store.chat.last?.id { proxy.scrollTo(id) } }
            }
            Divider()
            HStack(alignment: .bottom) {
                TextField("Ask Score…", text: $prompt, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...5)
                Button("Draft Slides", systemImage: "rectangle.stack.badge.plus") {
                    let text = prompt; prompt = ""; Task { await store.generateSlides(from: text) }
                }
                .help("Turn this descriptive scope into editable draft slides")
                .disabled(prompt.isEmpty || store.isWorking)
                Button("Send", systemImage: "arrow.up.circle.fill") { let text = prompt; prompt = ""; Task { await store.askAI(text) } }.labelStyle(.iconOnly).font(.title2).disabled(prompt.isEmpty || store.isWorking)
            }.padding()
        }
    }
}
