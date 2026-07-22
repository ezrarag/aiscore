import SwiftUI
import AVKit

struct StudioBackgroundView: View {
    let background: MediaBackground
    var body: some View {
        Group {
            switch background.kind {
            case .gradient:
                LinearGradient(colors: [.indigo, .black, .pink.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .generative:
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                    Canvas { context2D, size in
                        let t = context.date.timeIntervalSinceReferenceDate * max(0.05, background.motion)
                        context2D.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                        for i in 0..<7 {
                            let x = size.width * (0.5 + 0.38 * sin(t * 0.19 + Double(i)))
                            let y = size.height * (0.5 + 0.42 * cos(t * 0.13 + Double(i) * 1.7))
                            let radius = min(size.width, size.height) * (0.22 + Double(i % 3) * 0.06)
                            let color: Color = i.isMultiple(of: 2) ? .indigo : .pink
                            context2D.fill(Path(ellipseIn: CGRect(x: x-radius, y: y-radius, width: radius*2, height: radius*2)), with: .color(color.opacity(0.17)))
                        }
                    }
                }
            case .image:
                if let url = URL(string: background.source) {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.black }
                } else { Color.black }
            case .video:
                if let url = URL(string: background.source) { VideoPlayer(player: AVPlayer(url: url)).disabled(true) } else { Color.black }
            }
        }.overlay(.black.opacity(0.22))
    }
}

