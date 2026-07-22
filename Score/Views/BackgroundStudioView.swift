import SwiftUI
import PhotosUI

struct BackgroundStudioView: View {
    @Environment(ScoreStore.self) private var store
    @State private var prompt = ""
    @State private var remoteURL = ""
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Stage designer", systemImage: "photo.on.rectangle.angled").font(.headline)
                Picker("Mode", selection: $store.background.kind) {
                    Text("Living art").tag(BackgroundKind.generative)
                    Text("Image").tag(BackgroundKind.image)
                    Text("Video").tag(BackgroundKind.video)
                    Text("Gradient").tag(BackgroundKind.gradient)
                }.pickerStyle(.segmented)
                GroupBox("Generate with AI") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Describe the atmosphere", text: $prompt, axis: .vertical).textFieldStyle(.roundedBorder)
                        Button("Generate background", systemImage: "sparkles") { Task { await store.generateBackground(prompt: prompt) } }.disabled(prompt.isEmpty || store.isWorking)
                    }.padding(.vertical, 6)
                }
                GroupBox("Import") {
                    VStack(alignment: .leading, spacing: 10) {
                        PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose from Photos", systemImage: "photo") }
                        TextField("HTTPS image or video URL", text: $remoteURL).textFieldStyle(.roundedBorder)
                        Button("Use internet media", systemImage: "globe") {
                            guard let url = URL(string: remoteURL), ["https"].contains(url.scheme?.lowercased()) else { store.errorMessage = "Use a valid HTTPS URL."; return }
                            let ext = url.pathExtension.lowercased()
                            store.background.kind = ["mp4", "mov", "m3u8"].contains(ext) ? .video : .image
                            store.background.source = url.absoluteString
                        }
                    }.padding(.vertical, 6)
                }
                GroupBox("Motion") { Slider(value: $store.background.motion, in: 0...1) }
                Text("Internet media must permit remote display. Only use work you have permission to present.").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .task(id: photoItem) {
            guard let data = try? await photoItem?.loadTransferable(type: Data.self) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("score-background-\(UUID().uuidString).jpg")
            do { try data.write(to: url); store.background = MediaBackground(kind: .image, source: url.absoluteString, prompt: "Imported", motion: store.background.motion) }
            catch { store.errorMessage = error.localizedDescription }
        }
    }
}

