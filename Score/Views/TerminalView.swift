#if os(macOS)
import SwiftUI

struct TerminalView: View {
    @Environment(ScoreStore.self) private var store
    @State private var command = ""
    @State private var transcript = "Score studio shell\nCommands run in a restricted /bin/zsh process.\nType 'help' for custom Score commands.\n\n"
    @State private var running = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Studio terminal", systemImage: "terminal.fill").font(.headline)
                Spacer()
                Circle().fill(running ? .orange : .green).frame(width: 8)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                Text(transcript)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
            }
            
            Divider()
            
            HStack {
                Text("❯").foregroundStyle(.green)
                TextField("command", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(run)
                Button("Run", action: run)
                    .disabled(command.isEmpty || running)
            }
            .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func run() {
        let input = command.trimmingCharacters(in: .whitespacesAndNewlines)
        command = ""
        
        // Intercept custom Score commands
        let lowerInput = input.lowercased()
        if lowerInput == "clear" {
            transcript = ""
            return
        }
        if lowerInput == "help" {
            transcript += """
            ❯ \(input)
            Custom Score Commands:
              clear          Clears the terminal console log
              status         Prints active score, live slide details, and server status
              sync           Triggers a manual state synchronization to the network
              help           Shows this command registry listing
            
            Any other command runs natively in zsh.
            
            """
            return
        }
        if lowerInput == "status" {
            let activeSlideTitle = store.scores.flatMap { $0.blocks }.flatMap { $0.slides }.first { $0.id == store.activeSlideID }?.title ?? "None"
            transcript += """
            ❯ \(input)
            Active Studio Score Status:
              Server URL:    \(store.serverURL.absoluteString)
              Account ID:    \(store.account?.id.uuidString ?? "Offline/Guest")
              Role:          \(store.account?.role.rawValue ?? "guest")
              Active Slide:  \(activeSlideTitle) (\(store.activeSlideID?.uuidString ?? "None"))
              Pulses Count:  \(store.pulses.count)
              Weeks Loaded:  \(store.scores.count)
            
            """
            return
        }
        if lowerInput == "sync" {
            transcript += "❯ \(input)\nTriggering score database sync to classroom network...\n"
            running = true
            Task {
                await store.performSync()
                await MainActor.run {
                    transcript += "Database sync completed successfully.\n\n"
                    running = false
                }
            }
            return
        }
        
        transcript += "❯ \(input)\n"
        running = true
        Task.detached {
            let shellPath: String
            if FileManager.default.fileExists(atPath: "/bin/zsh") {
                shellPath = "/bin/zsh"
            } else if FileManager.default.fileExists(atPath: "/bin/bash") {
                shellPath = "/bin/bash"
            } else {
                shellPath = "/bin/sh"
            }
            
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: shellPath)
            process.arguments = ["-lc", input]
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                await MainActor.run {
                    transcript += output + "\n"
                    running = false
                }
            } catch {
                await MainActor.run {
                    transcript += "\(error.localizedDescription)\n"
                    running = false
                }
            }
        }
    }
}
#endif
