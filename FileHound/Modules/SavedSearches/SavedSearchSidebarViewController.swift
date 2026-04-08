import AppKit

final class SavedSearchSidebarViewController: NSViewController {
    override func loadView() {
        let container = NSView()

        let titleLabel = NSTextField(labelWithString: "已保存搜索")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16)
        ])

        view = container
    }
}
