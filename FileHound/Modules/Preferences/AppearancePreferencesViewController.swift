import AppKit
import SnapKit

final class AppearancePreferencesViewController: NSViewController {
    private let themePopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let fontSizeField = NSTextField()
    private let fontSizeStepper = NSStepper()
    private let dimColorButton = NSButton(title: "Choose Color", target: nil, action: nil)
    private let dimColorPreview = NSBox()

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.appearance.title"),
            subtitle: L10n.string("preferences.appearance.subtitle")
        )

        AppTheme.allCases.forEach { themePopup.addItem(withTitle: $0.displayName) }
        AppLanguage.allCases.forEach { languagePopup.addItem(withTitle: $0.displayName) }
        themePopup.setAccessibilityIdentifier("ThemePopup")
        languagePopup.setAccessibilityIdentifier("LanguagePopup")
        fontSizeField.setAccessibilityIdentifier("ResultsFontSizeField")
        dimColorButton.setAccessibilityIdentifier("DimColorButton")

        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)

        [themePopup, languagePopup, fontSizeField, dimColorButton].forEach {
            $0.alignment = .center
        }

        fontSizeField.stringValue = String(AppSettings.shared.resultsFontSize)
        fontSizeField.alignment = .center
        fontSizeStepper.minValue = 10
        fontSizeStepper.maxValue = 24
        fontSizeStepper.increment = 1
        fontSizeStepper.integerValue = AppSettings.shared.resultsFontSize
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeStepperChanged)

        dimColorPreview.boxType = .custom
        dimColorPreview.cornerRadius = 6
        dimColorPreview.fillColor = NSColor(hexString: AppSettings.shared.dimColorHex) ?? .quaternaryLabelColor
        dimColorPreview.borderColor = .separatorColor
        dimColorButton.target = self
        dimColorButton.action = #selector(cycleDimColor)

        let stack = NSStackView(views: [
            formRow(title: L10n.string("preferences.appearance.theme"), control: themePopup),
            formRow(title: L10n.string("preferences.appearance.language"), control: languagePopup),
            formRow(title: "Font Size", control: makeFontSizeControl()),
            formRow(title: "Dim Color", control: makeDimColorControl())
        ])
        stack.orientation = .vertical
        stack.spacing = 16

        rootView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalTo(rootView.contentGuide)
        }

        themePopup.selectItem(at: AppTheme.allCases.firstIndex(of: ThemeController.shared.currentTheme) ?? 0)
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: LocalizationController.shared.currentLanguage) ?? 0)

        view = rootView
    }

    @objc
    private func themeChanged() {
        ThemeController.shared.select(theme: AppTheme.allCases[themePopup.indexOfSelectedItem])
    }

    @objc
    private func languageChanged() {
        LocalizationController.shared.apply(language: AppLanguage.allCases[languagePopup.indexOfSelectedItem])
    }

    @objc
    private func fontSizeStepperChanged() {
        fontSizeField.stringValue = String(fontSizeStepper.integerValue)
        AppSettings.shared.resultsFontSize = fontSizeStepper.integerValue
    }

    @objc
    private func cycleDimColor() {
        let palette = ["#A0A7B3", "#8894A7", "#6E7E91"]
        let next = palette.first { $0 != AppSettings.shared.dimColorHex } ?? palette[0]
        AppSettings.shared.dimColorHex = next
        dimColorPreview.fillColor = NSColor(hexString: next) ?? .quaternaryLabelColor
    }

    private func makeFontSizeControl() -> NSView {
        let stack = NSStackView(views: [fontSizeField, fontSizeStepper])
        stack.orientation = .horizontal
        stack.spacing = 6
        fontSizeField.snp.makeConstraints { make in
            make.width.equalTo(70)
        }
        return stack
    }

    private func makeDimColorControl() -> NSView {
        let stack = NSStackView(views: [dimColorPreview, dimColorButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        dimColorPreview.snp.makeConstraints { make in
            make.width.equalTo(42)
            make.height.equalTo(24)
        }
        return stack
    }

    private func formRow(title: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        return row
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        let hex = hexString.replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
