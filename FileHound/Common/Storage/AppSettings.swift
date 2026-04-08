import Foundation

protocol KeyValueStoring {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func data(forKey key: String) -> Data?
    func set(_ value: Data, forKey key: String)
}

extension KeyValueStoring {
    func codableValue<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = data(forKey: key) else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func setCodable<T: Encodable>(_ value: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        set(data, forKey: key)
    }
}

final class InMemoryKeyValueStore: KeyValueStoring {
    private var strings: [String: String] = [:]
    private var values: [String: Data] = [:]

    func string(forKey key: String) -> String? {
        strings[key]
    }

    func set(_ value: String, forKey key: String) {
        strings[key] = value
    }

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func set(_ value: Data, forKey key: String) {
        values[key] = value
    }
}

final class AppSettings {
    private enum Keys {
        static let preferredTheme = "preferredTheme"
        static let preferredLanguage = "preferredLanguage"
    }

    private let storage: KeyValueStoring

    init(storage: KeyValueStoring = InMemoryKeyValueStore()) {
        self.storage = storage
    }

    var preferredTheme: AppTheme {
        get { AppTheme(rawValue: storage.string(forKey: Keys.preferredTheme) ?? AppTheme.system.rawValue) ?? .system }
        set { storage.set(newValue.rawValue, forKey: Keys.preferredTheme) }
    }

    var preferredLanguage: AppLanguage {
        get { AppLanguage(rawValue: storage.string(forKey: Keys.preferredLanguage) ?? AppLanguage.system.rawValue) ?? .system }
        set { storage.set(newValue.rawValue, forKey: Keys.preferredLanguage) }
    }
}
