import SwiftUI
import AVFoundation

struct VideoRecorderView: View {
    let onSave: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var session = AVCaptureSession()
    @State private var output = AVCaptureMovieFileOutput()
    @State private var isRecording = false
    @State private var hasCamera = true
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer? = nil
    
    private let coordinator = RecorderCoordinator()
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Record Slide Provocation").font(.headline)
                Spacer()
                Button("Cancel") {
                    stopAll()
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            if hasCamera {
                ZStack {
                    CameraPreviewView(session: session)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            if isRecording {
                                VStack {
                                    HStack {
                                        Circle().fill(.red).frame(width: 10, height: 10)
                                        Text(timeString(duration))
                                            .monospacedDigit()
                                            .foregroundStyle(.white)
                                    }
                                    .padding(8)
                                    .background(.black.opacity(0.6), in: Capsule())
                                    .padding()
                                    Spacer()
                                }
                            }
                        }
                }
                .frame(minWidth: 400, minHeight: 300)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash.fill").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Simulator Mode / Camera Unavailable").font(.headline)
                    Text("Using virtual mock recording.").font(.caption).foregroundStyle(.secondary)
                    
                    if isRecording {
                        HStack {
                            Circle().fill(.red).frame(width: 10, height: 10)
                            Text("Mock Recording... \(timeString(duration))")
                                .monospacedDigit()
                                .font(.title3)
                        }
                        .padding()
                    }
                }
                .frame(minWidth: 400, minHeight: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            
            HStack(spacing: 30) {
                if !isRecording {
                    Button(action: startRecording) {
                        Circle()
                            .fill(.red)
                            .frame(width: 60, height: 60)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: stopRecording) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.red)
                            .frame(width: 40, height: 40)
                            .frame(width: 60, height: 60)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom)
        }
        .padding()
        .onAppear {
            setupSession()
        }
        .onDisappear {
            stopAll()
        }
    }
    
    private func setupSession() {
        coordinator.onFinished = { url in
            onSave(url)
            dismiss()
        }
        
        let sessionQueue = DispatchQueue(label: "session.queue")
        sessionQueue.async {
            self.session.beginConfiguration()
            
            guard let videoDevice = AVCaptureDevice.default(for: .video),
                  let audioDevice = AVCaptureDevice.default(for: .audio) else {
                DispatchQueue.main.async { self.hasCamera = false }
                self.session.commitConfiguration()
                return
            }
            
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                
                if self.session.canAddInput(videoInput) { self.session.addInput(videoInput) }
                if self.session.canAddInput(audioInput) { self.session.addInput(audioInput) }
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                
                self.session.commitConfiguration()
                self.session.startRunning()
            } catch {
                DispatchQueue.main.async { self.hasCamera = false }
                self.session.commitConfiguration()
            }
        }
    }
    
    private func startRecording() {
        isRecording = true
        duration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            duration += 1
        }
        
        if hasCamera {
            let tempDir = FileManager.default.temporaryDirectory
            let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
            output.startRecording(to: outputURL, recordingDelegate: coordinator)
        }
    }
    
    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        isRecording = false
        
        if hasCamera {
            output.stopRecording()
        } else {
            // Mock mode returns a temporary dummy file path
            let tempDir = FileManager.default.temporaryDirectory
            let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
            try? Data().write(to: outputURL)
            onSave(outputURL)
            dismiss()
        }
    }
    
    private func stopAll() {
        timer?.invalidate()
        timer = nil
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    private func timeString(_ intervals: TimeInterval) -> String {
        let mins = Int(intervals) / 60
        let secs = Int(intervals) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

class RecorderCoordinator: NSObject, AVCaptureFileOutputRecordingDelegate {
    var onFinished: ((URL) -> Void)?
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        onFinished?(outputFileURL)
    }
}

#if os(macOS)
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.wantsLayer = true
        view.layer = layer
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#else
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}
#endif
