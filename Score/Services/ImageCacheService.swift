import SwiftUI
import Foundation

final class ImageCacheService: @unchecked Sendable {
    static let shared = ImageCacheService()
    
    private let cache: URLCache
    private let session: URLSession
    
    private init() {
        // 200 MB memory cache, 1 GB disk cache
        self.cache = URLCache(memoryCapacity: 200 * 1024 * 1024, diskCapacity: 1000 * 1024 * 1024, diskPath: "score_image_cache")
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }
    
    func fetchImage(from url: URL) async -> NSImage? {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        
        if let cachedResponse = cache.cachedResponse(for: request),
           let image = NSImage(data: cachedResponse.data) {
            return image
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            if let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
                let cachedResponse = CachedURLResponse(response: response, data: data)
                cache.storeCachedResponse(cachedResponse, for: request)
                return NSImage(data: data)
            }
        } catch {
            print("⚠️ Image load error for \(url): \(error.localizedDescription)")
        }
        return nil
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var nsImage: NSImage?
    @State private var isLoading = false
    @State private var hasFailed = false
    
    var body: some View {
        Group {
            if let nsImage {
                content(Image(nsImage: nsImage))
            } else if isLoading {
                placeholder()
            } else if hasFailed {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Image Unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.05))
            } else {
                placeholder()
                    .task {
                        await loadImage()
                    }
            }
        }
        .onChange(of: url) { _, _ in
            Task { await loadImage() }
        }
    }
    
    private func loadImage() async {
        guard let url else {
            hasFailed = true
            return
        }
        isLoading = true
        hasFailed = false
        if let img = await ImageCacheService.shared.fetchImage(from: url) {
            self.nsImage = img
            self.isLoading = false
        } else {
            self.isLoading = false
            self.hasFailed = true
        }
    }
}
