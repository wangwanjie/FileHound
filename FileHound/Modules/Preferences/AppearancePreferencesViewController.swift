import AppKit
import SnapKit

final class AppearancePreferencesViewController: NSViewController {
    private let themeLabel = NSTextField(labelWithString: "")
    private let themePopup = NSPopUpButton()
    private let languageLabel = NSTextField(labelWithString: "")
    private let languagePopup = NSPopUpButton()

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.appearance.title"),
            subtitle: L10n.string("preferences.appearance.subtitle")
        )

        themeLabel.stringValue = L10n.string("preferences.appearance.theme")
        languageLabel.stringValue = L10n.string("preferences.appearance.language")

        AppTheme.allCases.forEach { themePopup.addItem(withTitle: $0.displayName) }
        AppLanguage.allCases.forEach { languagePopup.addItem(withTitle: $0.displayName) }
        themePopup.setAccessibilityIdentifier("ThemePopup")
        languagePopup.setAccessibilityIdentifier("LanguagePopup")
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)

        rootView.addSubview(themeLabel)
        rootView.addSubview(themePopup)
        rootView.addSubview(languageLabel)
        rootView.addSubview(languagePopup)

        themeLabel.snp.makeConstraints { make in
            make.leading.top.equalTo(rootView.contentGuide)
        }
        themePopup.snp.makeConstraints { make in
            make.leading.equalTo(themeLabel.snp.trailing).offset(16)
            make.centerY.equalTo(themeLabel)
            make.width.equalTo(160)
        }
        languageLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.equalTo(themeLabel.snp.bottom).offset(16)
        }
        languagePopup.snp.makeConstraints { make in
            make.leading.equalTo(languageLabel.snp.trailing).offset(16)
            make.centerY.equalTo(languageLabel)
            make.width.equalTo(160)
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
}
