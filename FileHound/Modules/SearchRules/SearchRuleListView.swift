import AppKit
import SnapKit

final class SearchRuleListView: NSView {
    let stackView = NSStackView()
    let logicLabel = NSTextField(labelWithString: "All rules must match")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        setAccessibilityIdentifier("SearchRulesPanel")
        setAccessibilityElement(true)
        setAccessibilityLabel("SearchRulesPanel")
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.65).cgColor

        stackView.orientation = .vertical
        stackView.spacing = 10

        addSubview(stackView)
        addSubview(logicLabel)

        stackView.snp.makeConstraints { make in
            make.leading.top.trailing.equalToSuperview().inset(16)
        }
        logicLabel.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview().inset(16)
            make.top.equalTo(stackView.snp.bottom).offset(10)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
