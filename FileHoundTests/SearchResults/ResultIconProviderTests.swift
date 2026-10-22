import AppKit
import Testing
@testable import FileHound

struct ResultIconProviderTests {
    /// 记录加载器调用次数（加载器在 actor 外被并发调用，需要加锁）
    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    @Test
    func fallsBackToWorkspaceIconAndCachesResult() async {
        let thumbnailCalls = CallCounter()
        let workspaceCalls = CallCounter()
        // 兜底图标故意用 10×10 的图片，验证返回的是兜底加载结果并被调整为请求的尺寸
        let fallbackImage = NSImage(size: NSSize(width: 10, height: 10))
        let provider = ResultIconProvider(
            thumbnailLoader: { _ in
                thumbnailCalls.increment()
                return nil
            },
            workspaceIconLoader: { _ in
                workspaceCalls.increment()
                return fallbackImage
            }
        )
        let url = URL(fileURLWithPath: "/tmp/report.txt")

        let icon = await provider.icon(for: url, size: NSSize(width: 32, height: 32), preferThumbnail: true)
        #expect(icon != nil)
        #expect(icon?.size == NSSize(width: 32, height: 32))
        #expect(thumbnailCalls.count == 1)
        #expect(workspaceCalls.count == 1)

        // 相同参数再次请求命中缓存，不再调用任何加载器
        let cached = await provider.icon(for: url, size: NSSize(width: 32, height: 32), preferThumbnail: true)
        #expect(cached === icon)
        #expect(thumbnailCalls.count == 1)
        #expect(workspaceCalls.count == 1)

        // 不同尺寸是不同的缓存键，且不会改动已缓存图标的尺寸
        let larger = await provider.icon(for: url, size: NSSize(width: 64, height: 64), preferThumbnail: true)
        #expect(workspaceCalls.count == 2)
        #expect(larger?.size == NSSize(width: 64, height: 64))
        #expect(icon?.size == NSSize(width: 32, height: 32))
        #expect(fallbackImage.size == NSSize(width: 10, height: 10))
    }

    @Test
    func skipsThumbnailLoaderWhenThumbnailNotPreferred() async {
        let thumbnailCalls = CallCounter()
        let provider = ResultIconProvider(
            thumbnailLoader: { _ in
                thumbnailCalls.increment()
                return NSImage(size: NSSize(width: 1, height: 1))
            },
            workspaceIconLoader: { _ in NSImage(size: NSSize(width: 10, height: 10)) }
        )

        let icon = await provider.icon(for: URL(fileURLWithPath: "/tmp/a.txt"), size: NSSize(width: 16, height: 16), preferThumbnail: false)
        #expect(icon?.size == NSSize(width: 16, height: 16))
        #expect(thumbnailCalls.count == 0)
    }
}
