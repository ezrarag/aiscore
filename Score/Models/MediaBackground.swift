import Foundation

enum BackgroundKind: String, Codable, CaseIterable { case gradient, image, video, generative }

struct MediaBackground: Codable, Equatable {
    var kind: BackgroundKind = .generative
    var source: String = ""
    var prompt: String = "Slow luminous topography, midnight blue and electric coral"
    var motion: Double = 0.35
}

