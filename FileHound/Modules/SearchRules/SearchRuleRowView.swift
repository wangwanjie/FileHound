import AppKit
import SnapKit

final class SearchRuleRowView: NSView {
    let addButton = NSButton(title: "+", target: nil, action: nil)
    let removeButton = NSButton(title: "−", target: nil, action: nil)
    let fieldPopup = NSPopUpButton()
    let operatorPopup = NSPopUpButton()
    let valueField = NSTextField()

    init() {
        super.init(frame: .zero)

        SearchRuleField.allCases.forEach { fieldPopup.addItem(withTitle: $0.rawValue) }
        SearchRuleOperator.allCases.forEach { operatorPopup.addItem(withTitle: $0.rawValue) }

        fieldPopup.setAccessibilityIdentifier("SearchRuleFieldPopup")
        operatorPopup.setAccessibilityIdentifier("SearchRuleOperatorPopup")
        valueField.setAccessibilityIdentifier("SearchRuleValueField")
        valueField.stringValue = ".lookin"
        valueField.alignment = .center

        [addButton, removeButton, fieldPopup, operatorPopup, valueField].forEach(addSubview)

        addButton.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.size.equalTo(30)
        }
        removeButton.snp.makeConstraints { make in
            make.leading.equalTo(addButton.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(30)
        }
        fieldPopup.snp.makeConstraints { make in
            make.leading.equalTo(removeButton.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.width.equalTo(170)
        }
        operatorPopup.snp.makeConstraints { make in
            make.leading.equalTo(fieldPopup.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.width.equalTo(190)
        }
        valueField.snp.makeConstraints { make in
            make.leading.equalTo(operatorPopup.snp.trailing).offset(12)
            make.trailing.centerY.equalToSuperview()
            make.height.equalTo(36)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var selection: SearchRuleSelection {
        SearchRuleSelection(
            field: SearchRuleField.allCases[fieldPopup.indexOfSelectedItem],
            operator: SearchRuleOperator.allCases[operatorPopup.indexOfSelectedItem],
            value: valueField.stringValue
        )
    }

    func setEnabled(_ enabled: Bool) {
        [addButton, removeButton, fieldPopup, operatorPopup].forEach { $0.isEnabled = enabled }
        valueField.isEnabled = enabled
        alphaValue = enabled ? 1 : 0.55
    }
}
