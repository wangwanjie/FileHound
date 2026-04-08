import Combine
import Foundation

final class LocalizationController {
    static let shared = LocalizationController(settings: .shared)

    private let settings: AppSettings
    private let subject: CurrentValueSubject<AppLanguage, Never>

    var publisher: AnyPublisher<AppLanguage, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentLanguage: AppLanguage {
        subject.value
    }

    init(settings: AppSettings) {
        self.settings = settings
        self.subject = CurrentValueSubject(settings.preferredLanguage)
    }

    func localizedString(_ key: String) -> String {
        let bundle = bundle(for: currentLanguage) ?? .main
        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    func apply(language: AppLanguage) {
        settings.preferredLanguage = language
        subject.send(language)
    }

    private func bundle(for language: AppLanguage) -> Bundle? {
        guard language != .system else {
            return .main
        }

        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else {
            return .main
        }
        return Bundle(path: path)
    }
}
