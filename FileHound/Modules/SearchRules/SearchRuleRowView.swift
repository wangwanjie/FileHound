import AppKit
import SnapKit

final class SearchRuleRowView: NSView {
    let addButton = NSButton(title: "+", target: nil, action: nil)
    let removeButton = NSButton(title: "−", target: nil, action: nil)
    let fieldPopup = NSPopUpButton()
    let operatorPopup = NSPopUpButton()
    let valueField = NSTextField()
    let toggleValueControl = NSSegmentedControl(labels: ["Exclude", "Include"], trackingMode: .selectOne, target: nil, action: nil)
    private let valueContainer = NSView()
    private var currentOperators: [SearchRuleOperator] = SearchRuleField.name.definition.operators
    var onAdd: (() -> Void)?
    var onRemove: (() -> Void)?
    var onChange: (() -> Void)?

    init() {
        super.init(frame: .zero)

        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        fieldPopup.setAccessibilityIdentifier("SearchRuleFieldPopup")
        operatorPopup.setAccessibilityIdentifier("SearchRuleOperatorPopup")
        valueField.setAccessibilityIdentifier("SearchRuleValueField")
        toggleValueControl.setAccessibilityIdentifier("SearchRuleToggleValue")
        addButton.setAccessibilityIdentifier("SearchRuleAddButton")
        removeButton.setAccessibilityIdentifier("SearchRuleRemoveButton")
        valueField.stringValue = ".lookin"
        valueField.alignment = .natural
        valueField.font = .systemFont(ofSize: 14, weight: .regular)
        valueField.controlSize = .large
        valueField.isEditable = true
        valueField.isSelectable = true
        valueField.isBezeled = true
        valueField.drawsBackground = true
        valueField.focusRingType = .none
        valueField.lineBreakMode = .byTruncatingTail
        valueField.usesSingleLineMode = true
        valueField.maximumNumberOfLines = 1
        if let cell = valueField.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = true
            cell.usesSingleLineMode = true
            cell.lineBreakMode = .byTruncatingTail
        }
        fieldPopup.font = .systemFont(ofSize: 14, weight: .regular)
        fieldPopup.controlSize = .large
        operatorPopup.font = .systemFont(ofSize: 14, weight: .regular)
        operatorPopup.controlSize = .large
        toggleValueControl.font = .systemFont(ofSize: 13, weight: .regular)
        addButton.target = self
        addButton.action = #selector(addTapped)
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        fieldPopup.target = self
        fieldPopup.action = #selector(fieldChanged)
        operatorPopup.target = self
        operatorPopup.action = #selector(controlValueChanged)
        valueField.target = self
        valueField.action = #selector(controlValueChanged)
        valueField.delegate = self
        toggleValueControl.target = self
        toggleValueControl.action = #selector(controlValueChanged)
        [addButton, removeButton, fieldPopup, operatorPopup, valueContainer, valueField, toggleValueControl].forEach {
            $0.setContentHuggingPriority(.required, for: .vertical)
            $0.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        [addButton, removeButton, fieldPopup, operatorPopup, valueContainer].forEach(addSubview)
        [valueField, toggleValueControl].forEach(valueContainer.addSubview)

        addButton.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.size.equalTo(28)
        }
        removeButton.snp.makeConstraints { make in
            make.leading.equalTo(addButton.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(28)
        }
        fieldPopup.snp.makeConstraints { make in
            make.leading.equalTo(removeButton.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.width.equalTo(160)
            make.height.equalTo(32)
        }
        operatorPopup.snp.makeConstraints { make in
            make.leading.equalTo(fieldPopup.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.width.equalTo(170)
            make.height.equalTo(32)
        }
        valueContainer.snp.makeConstraints { make in
            make.leading.equalTo(operatorPopup.snp.trailing).offset(12)
            make.trailing.centerY.equalToSuperview()
            make.height.equalTo(32)
        }
        valueField.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        toggleValueControl.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.width.equalTo(190)
            make.height.equalTo(28)
        }

        reloadLocalizedStrings()
        updateEditor(for: .name, preferredOperator: .contains, preferredValue: valueField.stringValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var selection: SearchRuleSelection {
        let field = selectedField
        let editorValue: String

        switch field.definition.valueEditor {
        case .toggle:
            editorValue = toggleValueControl.selectedSegment == 1 ? "true" : "false"
        case .text, .number, .date:
            editorValue = valueField.stringValue
        }

        return SearchRuleSelection(
            field: field,
            operator: currentOperators[safe: operatorPopup.indexOfSelectedItem] ?? field.definition.operators.first ?? .contains,
            value: editorValue
        )
    }

    func apply(selection: SearchRuleSelection) {
        if let fieldIndex = SearchRuleField.allCases.firstIndex(of: selection.field) {
            fieldPopup.selectItem(at: fieldIndex)
        }
        updateEditor(for: selection.field, preferredOperator: selection.operator, preferredValue: selection.value)
    }

    func setEnabled(_ enabled: Bool) {
        [addButton, removeButton, fieldPopup, operatorPopup].forEach { $0.isEnabled = enabled }
        valueField.isEnabled = enabled
        toggleValueControl.isEnabled = enabled
        alphaValue = enabled ? 1 : 0.55
    }

    func setRemoveEnabled(_ enabled: Bool) {
        removeButton.isEnabled = enabled
    }

    func reloadLocalizedStrings() {
        let field = selectedField
        let searchOperator = currentOperators[safe: operatorPopup.indexOfSelectedItem] ?? field.definition.operators.first
        let editorValue = selection.value

        fieldPopup.removeAllItems()
        SearchRuleField.allCases.forEach { fieldPopup.addItem(withTitle: $0.localizedTitle) }
        if let fieldIndex = SearchRuleField.allCases.firstIndex(of: field) {
            fieldPopup.selectItem(at: fieldIndex)
        }

        updateEditor(for: field, preferredOperator: searchOperator, preferredValue: editorValue)
    }

    @objc
    private func addTapped() {
        onAdd?()
    }

    @objc
    private func fieldChanged() {
        updateEditor(for: selectedField, preferredOperator: selection.operator, preferredValue: selection.value)
        onChange?()
    }

    @objc
    private func controlValueChanged() {
        onChange?()
    }

    @objc
    private func removeTapped() {
        onRemove?()
    }

    private var selectedField: SearchRuleField {
        SearchRuleField.allCases[safe: fieldPopup.indexOfSelectedItem] ?? .name
    }

    private func updateEditor(
        for field: SearchRuleField,
        preferredOperator: SearchRuleOperator?,
        preferredValue: String
    ) {
        let definition = field.definition
        currentOperators = definition.operators

        operatorPopup.removeAllItems()
        operatorPopup.addItems(withTitles: currentOperators.map(\.localizedTitle))
        if let preferredOperator,
           let index = currentOperators.firstIndex(of: preferredOperator) {
            operatorPopup.selectItem(at: index)
        } else {
            operatorPopup.selectItem(at: 0)
        }

        switch definition.valueEditor {
        case .toggle(let falseLabel, let trueLabel):
            toggleValueControl.setLabel(falseLabel, forSegment: 0)
            toggleValueControl.setLabel(trueLabel, forSegment: 1)
            toggleValueControl.selectedSegment = SearchRuleSelection.booleanValue(from: preferredValue) ? 1 : 0
            toggleValueControl.isHidden = false
            valueField.isHidden = true
        case .text, .number, .date:
            valueField.placeholderString = definition.placeholder
            valueField.stringValue = preferredValue
            valueField.isHidden = false
            toggleValueControl.isHidden = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 44)
    }
}

extension SearchRuleRowView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let sanitizedValue = valueField.stringValue
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if sanitizedValue != valueField.stringValue {
            valueField.stringValue = sanitizedValue
        }
        onChange?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            window?.makeFirstResponder(nil)
            return true
        }

        return false
    }
}

#if DEBUG
extension SearchRuleRowView {
    var debugUsesToggleEditor: Bool {
        toggleValueControl.isHidden == false
    }
}
#endif

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
