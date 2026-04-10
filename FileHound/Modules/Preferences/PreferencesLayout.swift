import AppKit
import SnapKit

enum PreferencesLayout {
    static let windowWidth: CGFloat = 560
    static let contentWidth: CGFloat = 500
    static let minWindowHeight: CGFloat = 260
    static let maxWindowHeight: CGFloat = 430
    static let labelWidth: CGFloat = 145
}

func makePreferencesFormRow(title: String, control: NSView) -> NSView {
    let row = NSView()
    let titleLabel = NSTextField(labelWithString: title)

    row.addSubview(titleLabel)
    row.addSubview(control)

    titleLabel.snp.makeConstraints { make in
        make.leading.top.bottom.equalToSuperview()
        make.width.equalTo(PreferencesLayout.labelWidth)
    }
    control.snp.makeConstraints { make in
        make.leading.equalTo(titleLabel.snp.trailing).offset(12)
        make.top.bottom.trailing.equalToSuperview()
    }

    return row
}
