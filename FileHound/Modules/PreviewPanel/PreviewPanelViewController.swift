import AppKit
import SnapKit

final class PreviewPanelViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "预览")
    private let reasonLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let rootView = NSView()

        titleLabel.stringValue = L10n.string("preview.title")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        reasonLabel.setAccessibilityIdentifier("PreviewReason")

        rootView.addSubview(titleLabel)
        rootView.addSubview(reasonLabel)
        rootView.addSubview(snippetLabel)

        titleLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(20)
        }
        reasonLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.top.equalTo(titleLabel.snp.bottom).offset(16)
        }
        snippetLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.top.equalTo(reasonLabel.snp.bottom).offset(8)
        }

        view = rootView
    }

    func render(_ item: SearchResultItem?) {
        reasonLabel.stringValue = item?.matchReason ?? ""
        snippetLabel.stringValue = item?.previewSnippet ?? ""
    }
}
