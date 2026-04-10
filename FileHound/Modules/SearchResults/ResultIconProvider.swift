import AppKit
import QuickLookThumbnailing

actor ResultIconProvider {
    private var cache: [String: NSImage] = [:]
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
        if let cached = cache[cacheKey] {
            return cached
        }

        let image = await loadIcon(for: url, size: size, preferThumbnail: preferThumbnail)
        if let image {
            cache[cacheKey] = image
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
