import AppKit
import Testing
@testable import FileHound

struct ResultIconProviderTests {
    @Test
    func fallsBackToWorkspaceIconWhenThumbnailUnavailable() async {
        let provider = ResultIconProvider(
            thumbnailLoader: { _ in nil },
            workspaceIconLoader: { _ in NSImage(size: NSSize(width: 32, height: 32)) }
        )

        let icon = await provider.icon(
            for: URL(fileURLWithPath: "/tmp/report.txt"),
            size: NSSize(width: 32, height: 32),
            preferThumbnail: true
        )

        #expect(icon != nil)
        #expect(icon?.size == NSSize(width: 32, height: 32))
    }
}
