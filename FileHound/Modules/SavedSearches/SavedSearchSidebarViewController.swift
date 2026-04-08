import AppKit
import SnapKit

final class SavedSearchSidebarViewController: NSViewController {
    override func loadView() {
        let container = NSView()

        let titleLabel = NSTextField(labelWithString: L10n.string("sidebar.saved_searches"))
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        container.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(16)
        }

        view = container
    }
}
