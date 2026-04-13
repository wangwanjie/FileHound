import AppKit
import SnapKit

final class SearchRuleRowView: NSView {
    let addButton = NSButton(title: "+", target: nil, action: nil)
    let removeButton = NSButton(title: "−", target: nil, action: nil)
    let fieldPopup = NSPopUpButton()
    let operatorPopup = NSPopUpButton()
    let valueField = NSTextField()
    let toggleValueControl = NSSegmentedControl(labels: ["Exclude", "Include"], trackingMode: .selectOne, target: nil, action: nil)
    private let choiceValuePopup = NSPopUpButton()
    private let relativeValueContainer = NSView()
    private let relativeAmountField = NSTextField()
    private let relativeUnitPopup = NSPopUpButton()
    private let valueContainer = NSView()
    private let validationLabel = NSTextField(labelWithString: "")
    private var validationHeightConstraint: Constraint?
    private var validationTopConstraint: Constraint?
    private var currentOperators: [SearchRuleOperatorDefinition] = SearchRuleField.name.definition.operators
    private var currentValidationResult: SearchRuleValidationResult = .valid
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
        choiceValuePopup.setAccessibilityIdentifier("SearchRuleChoiceValuePopup")
        relativeAmountField.setAccessibilityIdentifier("SearchRuleRelativeAmountField")
        relativeUnitPopup.setAccessibilityIdentifier("SearchRuleRelativeUnitPopup")

        configureTextField(valueField, defaultValue: "")
        configureTextField(relativeAmountField, defaultValue: "")
        relativeAmountField.alignment = .right
        relativeAmountField.placeholderString = L10n.string("search_rule.placeholder.amount")

        fieldPopup.font = .systemFont(ofSize: 14, weight: .regular)
        fieldPopup.controlSize = .large
        operatorPopup.font = .systemFont(ofSize: 14, weight: .regular)
        operatorPopup.controlSize = .large
        choiceValuePopup.font = .systemFont(ofSize: 14, weight: .regular)
        choiceValuePopup.controlSize = .large
        relativeUnitPopup.font = .systemFont(ofSize: 14, weight: .regular)
        relativeUnitPopup.controlSize = .large
        toggleValueControl.font = .systemFont(ofSize: 13, weight: .regular)

        validationLabel.font = .systemFont(ofSize: 12, weight: .regular)
        validationLabel.textColor = .secondaryLabelColor
        validationLabel.lineBreakMode = .byTruncatingTail
        validationLabel.maximumNumberOfLines = 1
        validationLabel.isHidden = true

        addButton.target = self
        addButton.action = #selector(addTapped)
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        fieldPopup.target = self
        fieldPopup.action = #selector(fieldChanged)
        operatorPopup.target = self
        operatorPopup.action = #selector(operatorChanged)
        valueField.target = self
        valueField.action = #selector(controlValueChanged)
        valueField.delegate = self
        toggleValueControl.target = self
        toggleValueControl.action = #selector(controlValueChanged)
        choiceValuePopup.target = self
        choiceValuePopup.action = #selector(controlValueChanged)
        relativeAmountField.target = self
        relativeAmountField.action = #selector(controlValueChanged)
        relativeAmountField.delegate = self
        relativeUnitPopup.target = self
        relativeUnitPopup.action = #selector(controlValueChanged)

        [addButton, removeButton, fieldPopup, operatorPopup, valueContainer, valueField, toggleValueControl, choiceValuePopup, relativeValueContainer, relativeAmountField, relativeUnitPopup].forEach {
            $0.setContentHuggingPriority(.required, for: .vertical)
            $0.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        [addButton, removeButton, fieldPopup, operatorPopup, valueContainer, validationLabel].forEach(addSubview)
        [valueField, toggleValueControl, choiceValuePopup, relativeValueContainer].forEach(valueContainer.addSubview)
        [relativeAmountField, relativeUnitPopup].forEach(relativeValueContainer.addSubview)

        addButton.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalTo(valueContainer)
            make.size.equalTo(28)
        }
        removeButton.snp.makeConstraints { make in
            make.leading.equalTo(addButton.snp.trailing).offset(8)
            make.centerY.equalTo(valueContainer)
            make.size.equalTo(28)
        }
        fieldPopup.snp.makeConstraints { make in
            make.leading.equalTo(removeButton.snp.trailing).offset(12)
            make.centerY.equalTo(valueContainer)
            make.width.equalTo(160)
            make.height.equalTo(32)
        }
        operatorPopup.snp.makeConstraints { make in
            make.leading.equalTo(fieldPopup.snp.trailing).offset(12)
            make.centerY.equalTo(valueContainer)
            make.width.equalTo(170)
            make.height.equalTo(32)
        }
        valueContainer.snp.makeConstraints { make in
            make.leading.equalTo(operatorPopup.snp.trailing).offset(12)
            make.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(6)
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
        choiceValuePopup.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        relativeValueContainer.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        relativeAmountField.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalTo(84)
        }
        relativeUnitPopup.snp.makeConstraints { make in
            make.leading.equalTo(relativeAmountField.snp.trailing).offset(8)
            make.trailing.top.bottom.equalToSuperview()
        }
        validationLabel.snp.makeConstraints { make in
            make.leading.equalTo(fieldPopup)
            self.validationTopConstraint = make.top.equalTo(valueContainer.snp.bottom).offset(0).constraint
            make.trailing.lessThanOrEqualToSuperview()
            self.validationHeightConstraint = make.height.equalTo(0).constraint
            make.bottom.equalToSuperview().inset(6)
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
        let operatorDefinition = currentOperators[safe: operatorPopup.indexOfSelectedItem] ?? field.definition.operators.first
        let editorValue: String

        switch field.definition.valueEditor(for: operatorDefinition?.op) {
        case .toggle:
            editorValue = toggleValueControl.selectedSegment == 1 ? "true" : "false"
        case .choice(let options):
            editorValue = options[safe: choiceValuePopup.indexOfSelectedItem]?.id ?? ""
        case .relativeDate:
            editorValue = SearchRuleRelativeDateValue.encode(amountText: relativeAmountField.stringValue, unit: selectedRelativeUnit)
        case .none:
            editorValue = ""
        case .text, .number, .date:
            editorValue = valueField.stringValue
        }

        return SearchRuleSelection(
            field: field,
            operator: operatorDefinition?.op ?? field.definition.operators.first?.op ?? .contains,
            value: editorValue
        )
    }

    func apply(selection: SearchRuleSelection) {
        if let fieldIndex = SearchRuleField.allCases.firstIndex(of: selection.field) {
            fieldPopup.selectItem(at: fieldIndex)
        }
        updateEditor(for: selection.field, preferredOperator: selection.operator, preferredValue: selection.value)
    }

    func applyValidation(_ result: SearchRuleValidationResult) {
        currentValidationResult = result
        validationLabel.stringValue = result.blockingMessage ?? ""
        let isVisible = result != .valid
        validationLabel.isHidden = isVisible == false
        validationTopConstraint?.update(offset: isVisible ? 4 : 0)
        validationHeightConstraint?.update(offset: isVisible ? 16 : 0)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func setEnabled(_ enabled: Bool) {
        [addButton, removeButton, fieldPopup, operatorPopup].forEach { $0.isEnabled = enabled }
        valueField.isEnabled = enabled
        toggleValueControl.isEnabled = enabled
        choiceValuePopup.isEnabled = enabled
        relativeAmountField.isEnabled = enabled
        relativeUnitPopup.isEnabled = enabled
        alphaValue = enabled ? 1 : 0.55
    }

    func setRemoveEnabled(_ enabled: Bool) {
        removeButton.isEnabled = enabled
    }

    func reloadLocalizedStrings() {
        let selection = self.selection
        populateFieldPopup(selecting: selection.field)
        updateEditor(for: selection.field, preferredOperator: selection.operator, preferredValue: selection.value)
        applyValidation(currentValidationResult)
    }

    @objc
    private func addTapped() {
        onAdd?()
    }

    @objc
    private func fieldChanged() {
        let preferredValue = selection.value
        updateEditor(for: selectedField, preferredOperator: selection.operator, preferredValue: preferredValue)
        onChange?()
    }

    @objc
    private func operatorChanged() {
        let currentValue = selection.value
        let preferredOperator = currentOperators[safe: operatorPopup.indexOfSelectedItem]?.op
        updateEditor(for: selectedField, preferredOperator: preferredOperator, preferredValue: currentValue)
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

    private var selectedRelativeUnit: SearchRuleRelativeDateUnit? {
        relativeUnitPopup.selectedItem?.representedObject as? SearchRuleRelativeDateUnit
    }

    private func updateEditor(
        for field: SearchRuleField,
        preferredOperator: SearchRuleOperator?,
        preferredValue: String
    ) {
        let definition = field.definition
        populateFieldPopup(selecting: field)
        currentOperators = definition.operators
        populateOperatorPopup(with: currentOperators)

        if let preferredOperator,
           let index = currentOperators.firstIndex(where: { $0.op == preferredOperator }) {
            operatorPopup.selectItem(at: index)
        } else {
            operatorPopup.selectItem(at: 0)
        }

        let selectedOperator = currentOperators[safe: operatorPopup.indexOfSelectedItem]?.op
        let editorKind = definition.valueEditor(for: selectedOperator)
        valueField.placeholderString = definition.placeholder(for: selectedOperator)

        switch editorKind {
        case .toggle(let falseLabel, let trueLabel):
            toggleValueControl.setLabel(falseLabel, forSegment: 0)
            toggleValueControl.setLabel(trueLabel, forSegment: 1)
            toggleValueControl.selectedSegment = SearchRuleSelection.booleanValue(from: preferredValue) ? 1 : 0
        case .choice(let options):
            populateChoicePopup(with: options, selectedValue: preferredValue)
        case .relativeDate(let units):
            let parsed = SearchRuleRelativeDateValue.parse(preferredValue)
            relativeAmountField.stringValue = parsed.amountText
            populateRelativeUnitPopup(with: units, selectedUnit: parsed.unit)
        case .none:
            break
        case .text, .number, .date:
            valueField.stringValue = preferredValue
        }

        valueField.isHidden = true
        toggleValueControl.isHidden = true
        choiceValuePopup.isHidden = true
        relativeValueContainer.isHidden = true

        switch editorKind {
        case .toggle:
            toggleValueControl.isHidden = false
        case .choice:
            choiceValuePopup.isHidden = false
        case .relativeDate:
            relativeValueContainer.isHidden = false
        case .none:
            break
        case .text, .number, .date:
            valueField.isHidden = false
        }
    }

    private func populateFieldPopup(selecting field: SearchRuleField) {
        fieldPopup.removeAllItems()
        for currentField in SearchRuleField.allCases {
            fieldPopup.addItem(withTitle: currentField.localizedTitle)
            fieldPopup.item(at: fieldPopup.numberOfItems - 1)?.isEnabled = currentField.definition.isSupported
        }
        if let fieldIndex = SearchRuleField.allCases.firstIndex(of: field) {
            fieldPopup.selectItem(at: fieldIndex)
        }
    }

    private func populateOperatorPopup(with definitions: [SearchRuleOperatorDefinition]) {
        operatorPopup.removeAllItems()
        for definition in definitions {
            operatorPopup.addItem(withTitle: definition.localizedTitle)
            operatorPopup.item(at: operatorPopup.numberOfItems - 1)?.isEnabled = definition.isSupported
        }
    }

    private func populateChoicePopup(with options: [SearchRuleChoiceOption], selectedValue: String) {
        choiceValuePopup.removeAllItems()
        for option in options {
            choiceValuePopup.addItem(withTitle: option.localizedTitle)
        }

        if let index = options.firstIndex(where: { $0.id == selectedValue }) {
            choiceValuePopup.selectItem(at: index)
        } else {
            choiceValuePopup.selectItem(at: 0)
        }
    }

    private func populateRelativeUnitPopup(with units: [SearchRuleRelativeDateUnit], selectedUnit: SearchRuleRelativeDateUnit?) {
        relativeUnitPopup.removeAllItems()
        let placeholder = NSMenuItem(title: L10n.string("search_rule.placeholder.unit"), action: nil, keyEquivalent: "")
        placeholder.representedObject = nil
        relativeUnitPopup.menu?.addItem(placeholder)
        for unit in units {
            let item = NSMenuItem(title: unit.localizedTitle, action: nil, keyEquivalent: "")
            item.representedObject = unit
            relativeUnitPopup.menu?.addItem(item)
        }

        if let selectedUnit,
           let index = relativeUnitPopup.menu?.items.firstIndex(where: { ($0.representedObject as? SearchRuleRelativeDateUnit) == selectedUnit }) {
            relativeUnitPopup.select(relativeUnitPopup.menu!.items[index])
        } else {
            relativeUnitPopup.selectItem(at: 0)
        }
    }

    private func configureTextField(_ textField: NSTextField, defaultValue: String) {
        textField.stringValue = defaultValue
        textField.alignment = .natural
        textField.font = .systemFont(ofSize: 14, weight: .regular)
        textField.controlSize = .large
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBezeled = true
        textField.drawsBackground = true
        textField.focusRingType = .none
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        textField.maximumNumberOfLines = 1
        if let cell = textField.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = true
            cell.usesSingleLineMode = true
            cell.lineBreakMode = .byTruncatingTail
        }
    }

    override var intrinsicContentSize: NSSize {
        let extraHeight: CGFloat = currentValidationResult == .valid ? 44 : 58
        return NSSize(width: NSView.noIntrinsicMetric, height: extraHeight)
    }
}

extension SearchRuleRowView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let field = (obj.object as? NSTextField) ?? activeEditableField()
        let sanitizedValue = field.stringValue
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if sanitizedValue != field.stringValue {
            field.stringValue = sanitizedValue
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

    private func activeEditableField() -> NSTextField {
        relativeValueContainer.isHidden ? valueField : relativeAmountField
    }
}

#if DEBUG
extension SearchRuleRowView {
    var debugUsesToggleEditor: Bool {
        toggleValueControl.isHidden == false
    }

    var debugUsesChoiceEditor: Bool {
        choiceValuePopup.isHidden == false
    }

    var debugUsesRelativeDateEditor: Bool {
        relativeValueContainer.isHidden == false
    }

    var debugValidationMessage: String {
        validationLabel.stringValue
    }
}
#endif

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
