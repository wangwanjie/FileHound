import AppKit
import QuickLookThumbnailing

actor ResultIconProvider {
    /// 图标缓存用 NSCache：限制条目数，内存紧张时系统可自动回收，避免结果很多时无限增长
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 2000
        return cache
    }()
    private let thumbnailLoader: @Sendable (URL) async -> NSImage?
    private let workspaceIconLoader: @Sendable (URL) -> NSImage

    init(
        thumbnailLoader: @escaping @Sendable (URL) async -> NSImage? = { url in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 128, height: 128),
                scale: 2,
                representationTypes: .thumbnail
            )
            guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
                return nil
            }
            return representation.nsImage
        },
        workspaceIconLoader: @escaping @Sendable (URL) -> NSImage = { url in
            NSWorkspace.shared.icon(forFile: url.path)
        }
    ) {
        self.thumbnailLoader = thumbnailLoader
        self.workspaceIconLoader = workspaceIconLoader
    }

    func icon(for url: URL, size: NSSize, preferThumbnail: Bool) async -> NSImage? {
        let cacheKey = "\(url.path)#\(Int(size.width))x\(Int(size.height))#\(preferThumbnail)"
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let image = await loadIcon(for: url, size: size, preferThumbnail: preferThumbnail)
        if let image {
            cache.setObject(image, forKey: cacheKey as NSString)
        }
        return image
    }

    private func loadIcon(for url: URL, size: NSSize, preferThumbnail: Bool) async -> NSImage? {
        if preferThumbnail, let thumbnail = await thumbnailLoader(url) {
            thumbnail.size = size
            return thumbnail
        }

        let icon = workspaceIconLoader(url)
        icon.size = size
        return icon
    }
}
