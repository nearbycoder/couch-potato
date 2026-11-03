import SwiftUI
import ImageIO

/// Fetches, downsamples and caches box art so big poster walls scroll smoothly.
actor ImagePipeline {
    static let shared = ImagePipeline()

    nonisolated(unsafe) private let cache = NSCache<NSString, PlatformImage>()
    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]

    init() { cache.countLimit = 400 }

    nonisolated func cached(_ url: URL, maxPixel: CGFloat) -> PlatformImage? {
        cache.object(forKey: Self.key(url, maxPixel))
    }

    func image(_ url: URL, maxPixel: CGFloat) async -> PlatformImage? {
        let key = Self.key(url, maxPixel)
        if let hit = cache.object(forKey: key) { return hit }
        if let task = inFlight[key as String] { return await task.value }
        let task = Task<PlatformImage?, Never>.detached(priority: .userInitiated) {
            guard let (data, _) = try? await HTTP.session.data(from: url) else { return nil }
            return Self.downsample(data, maxPixel: maxPixel)
        }
        inFlight[key as String] = task
        let image = await task.value
        inFlight[key as String] = nil
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    private static func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(maxPixel))" as NSString
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> PlatformImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        #if os(iOS)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #endif
    }
}

/// Box art with a whimsical placeholder while it loads (or if there is none).
struct RemoteImage: View {
    var url: URL?
    var maxPixel: CGFloat = 600
    var placeholderTitle: String?
    var contentMode: ContentMode = .fill

    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                PosterPlaceholder(title: placeholderTitle)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImagePipeline.shared.cached(url, maxPixel: maxPixel) { image = hit; return }
            let loaded = await ImagePipeline.shared.image(url, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}

struct PosterPlaceholder: View {
    var title: String?

    var body: some View {
        ZStack {
            Theme.surfaceElevated
            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(Theme.textTertiary)
                if let title {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 8)
                }
            }
        }
    }
}
