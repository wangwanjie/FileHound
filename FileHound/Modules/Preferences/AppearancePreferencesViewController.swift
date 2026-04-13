import AppKit
import SnapKit

final class AppearancePreferencesViewController: NSViewController {
    private let settings: AppSettings
    private let themeController: ThemeController
    private let localizationController: LocalizationController
    private let themePopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let fontSizeField = NSTextField()
    private let fontSizeStepper = NSStepper()
    private let dimColorButton = NSButton(title: "", target: nil, action: nil)
    private let dimColorPreview = NSBox()
    private let resetButton = NSButton(title: "", target: nil, action: nil)
    private let dimColorPanel = NSColorPanel.shared

    init(
        settings: AppSettings = .shared,
        themeController: ThemeController = .shared,
        localizationController: LocalizationController = .shared
    ) {
        self.settings = settings
        self.themeController = themeController
        self.localizationController = localizationController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
        dimColorButton.title = L10n.string("preferences.appearance.choose_color")
        resetButton.title = L10n.string("preferences.reset_defaults")
        fontSizeField.alignment = .left
        fontSizeStepper.minValue = 10
        fontSizeStepper.maxValue = 24
        fontSizeStepper.increment = 1
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeStepperChanged)

        dimColorPreview.boxType = .custom
        dimColorPreview.cornerRadius = 6
        dimColorPreview.borderWidth = 1
        dimColorButton.target = self
        dimColorButton.action = #selector(showDimColorPanel)
        resetButton.target = self
        resetButton.action = #selector(resetDefaults)

        let stack = NSStackView(views: [
            makePreferencesFormRow(title: L10n.string("preferences.appearance.theme"), control: themePopup),
            makePreferencesFormRow(title: L10n.string("preferences.appearance.language"), control: languagePopup),
            makePreferencesFormRow(title: L10n.string("preferences.appearance.font_size"), control: makeFontSizeControl()),
            makePreferencesFormRow(title: L10n.string("preferences.appearance.dim_color"), control: makeDimColorControl()),
            resetButton
        ])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .leading

        rootView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalTo(rootView.contentGuide)
        }

        syncFromSettings()
        view = rootView
    }

    @objc
    private func themeChanged() {
        themeController.select(theme: AppTheme.allCases[themePopup.indexOfSelectedItem])
    }

    @objc
    private func languageChanged() {
        localizationController.apply(language: AppLanguage.allCases[languagePopup.indexOfSelectedItem])
    }

    @objc
    private func fontSizeStepperChanged() {
        fontSizeField.stringValue = String(fontSizeStepper.integerValue)
        settings.resultsFontSize = fontSizeStepper.integerValue
    }

    @objc
    private func showDimColorPanel() {
        dimColorPanel.setTarget(self)
        dimColorPanel.setAction(#selector(dimColorChanged(_:)))
        dimColorPanel.isContinuous = true
        dimColorPanel.color = NSColor(hexString: settings.dimColorHex) ?? .quaternaryLabelColor
        dimColorPanel.orderFront(nil)
    }

    @objc
    private func dimColorChanged(_ sender: NSColorPanel) {
        applyDimColor(sender.color)
    }

    @objc
    private func resetDefaults() {
        let defaults = AppearancePreferences()
        themeController.select(theme: defaults.preferredTheme)
        localizationController.apply(language: defaults.preferredLanguage)
        settings.resultsFontSize = defaults.resultsFontSize
        settings.dimColorHex = defaults.dimColorHex
        syncFromSettings()
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

    private func syncFromSettings() {
        themePopup.selectItem(at: AppTheme.allCases.firstIndex(of: themeController.currentTheme) ?? 0)
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: localizationController.currentLanguage) ?? 0)
        fontSizeField.stringValue = String(settings.resultsFontSize)
        fontSizeStepper.integerValue = settings.resultsFontSize
        dimColorPreview.borderColor = .separatorColor
        dimColorPreview.fillColor = NSColor(hexString: settings.dimColorHex) ?? .quaternaryLabelColor
    }

    private func applyDimColor(_ color: NSColor) {
        let normalized = color.usingColorSpace(.deviceRGB) ?? color
        guard let hex = normalized.hexString else {
            return
        }

        settings.dimColorHex = hex
        dimColorPreview.fillColor = normalized
    }
}

#if DEBUG
extension AppearancePreferencesViewController {
    func debugSelectTheme(_ theme: AppTheme) {
        themePopup.selectItem(at: AppTheme.allCases.firstIndex(of: theme) ?? 0)
        themeChanged()
    }

    func debugSelectLanguage(_ language: AppLanguage) {
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: language) ?? 0)
        languageChanged()
    }

    func debugTriggerResetDefaults() {
        resetDefaults()
    }

    var debugSelectedTheme: AppTheme {
        AppTheme.allCases[themePopup.indexOfSelectedItem]
    }

    var debugSelectedLanguage: AppLanguage {
        AppLanguage.allCases[languagePopup.indexOfSelectedItem]
    }

    var debugFontSizeValue: Int {
        fontSizeStepper.integerValue
    }

    var debugDimColorHex: String {
        settings.dimColorHex
    }

    var debugDimColorPreviewHex: String {
        dimColorPreview.fillColor.hexString ?? ""
    }

    func debugApplyDimColor(_ color: NSColor) {
        applyDimColor(color)
    }
}
#endif

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

    var hexString: String? {
        let color = usingColorSpace(.deviceRGB) ?? self
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
