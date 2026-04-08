import AppKit

final class PreviewPanelViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "预览")
    private let reasonLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let rootView = NSView()

        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        reasonLabel.translatesAutoresizingMaskIntoConstraints = false
        reasonLabel.setAccessibilityIdentifier("PreviewReason")
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(titleLabel)
        rootView.addSubview(reasonLabel)
        rootView.addSubview(snippetLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20),

            reasonLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            reasonLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            reasonLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),

            snippetLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            snippetLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            snippetLabel.topAnchor.constraint(equalTo: reasonLabel.bottomAnchor, constant: 8)
        ])

        view = rootView
    }

    func render(_ item: SearchResultItem?) {
        reasonLabel.stringValue = item?.matchReason ?? ""
        snippetLabel.stringValue = item?.previewSnippet ?? ""
    }
}
