import Foundation
import MMKV

enum UpdateCheckPolicy: String, Codable, Sendable {
    case onLaunch
    case manualOnly
    case dailyAutomatic
}

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

/// 逐元素宽容解码的包装：单个元素解码失败时记为 nil，而不是让整个数组解码失败
struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// 宽容读取数组的结果
struct LenientDecodedArray<Element> {
    var elements: [Element]
    /// 存储中有数据，但其中部分元素（或整体）无法完整解码。此时写回会丢失原始数据，需要先备份
    var isLossy: Bool

    static var empty: LenientDecodedArray<Element> {
        LenientDecodedArray(elements: [], isLossy: false)
    }
}

extension KeyValueStoring {
    /// 备份键：原始数据无法完整解码时，写回前先把原始 data 复制到这里，避免用户数据被永久覆盖
    static func backupKey(for key: String) -> String {
        key + ".backup"
    }

    /// 逐元素宽容读取数组：跳过无法解码的坏元素，保留其余元素
    func lenientArray<Element: Decodable>(_ type: Element.Type, forKey key: String) -> LenientDecodedArray<Element> {
        guard let data = data(forKey: key) else {
            return .empty
        }
        guard let wrapped = try? JSONDecoder().decode([FailableDecodable<Element>].self, from: data) else {
            // 整体不是合法的 JSON 数组：读出空数组，但标记为有损，写回前需要备份
            return LenientDecodedArray(elements: [], isLossy: true)
        }
        let elements = wrapped.compactMap(\.value)
        return LenientDecodedArray(elements: elements, isLossy: elements.count != wrapped.count)
    }

    /// 把当前原始数据备份到 `<key>.backup`。仅在即将用有损结果覆盖原数据前调用
    func backupRawValue(forKey key: String) {
        guard let data = data(forKey: key) else {
            return
        }
        set(data, forKey: Self.backupKey(for: key))
    }
}

/// 运行环境识别：单元测试 / UI 测试时需要隔离用户数据并跳过启动副作用
enum AppRuntimeEnvironment {
    /// UI 测试通过启动参数 `--uitesting` 启动 App
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    /// 作为单元测试的 test host 运行：XCTest 会注入 XCTestConfigurationFilePath 环境变量（UI 测试中的 App 进程不受影响）
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil && isUITesting == false
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

final class MMKVKeyValueStore: KeyValueStoring {
    static let shared = MMKVKeyValueStore()

    private let mmkv: MMKV

    static func initializeStore() {
        // UI 测试会通过启动参数改写偏好，单元测试的 test host 也会读写 .shared，均使用独立目录，避免污染用户真实的设置
        let directoryName: String
        if AppRuntimeEnvironment.isUITesting {
            directoryName = "MMKV-UITesting"
        } else if AppRuntimeEnvironment.isRunningUnitTests {
            directoryName = "MMKV-UnitTesting"
        } else {
            directoryName = "MMKV"
        }
        let rootURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FileHound", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        MMKV.initialize(rootDir: rootURL.path)
    }

    private init() {
        // 不能先用 MMKV.default() 判断是否已初始化：未初始化时访问它会触发 libMMKV 的 NSAssert（Debug 下崩溃）。
        // MMKV.initialize 重复调用会被忽略（libMMKV 内部有 g_hasCalledInitializeMMKV 标记），因此这里无条件调用
        Self.initializeStore()
        guard let mmkv = MMKV.default() else {
            fatalError("MMKV 初始化失败")
        }
        self.mmkv = mmkv
    }

    func string(forKey key: String) -> String? {
        mmkv.string(forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        mmkv.set(value, forKey: key)
    }

    func data(forKey key: String) -> Data? {
        mmkv.data(forKey: key)
    }

    func set(_ value: Data, forKey key: String) {
        mmkv.set(value, forKey: key)
    }
}

final class AppSettings {
    private enum Keys {
        static let preferredTheme = "preferredTheme"
        static let preferredLanguage = "preferredLanguage"
        static let updateCheckPolicy = "updateCheckPolicy"
        static let resultsFontSize = "resultsFontSize"
        static let dimColorHex = "dimColorHex"
        static let autoDownloadUpdates = "autoDownloadUpdates"
        static let launchShortcut = "launchShortcut"
        static let activationMode = "activationMode"
        static let openRecentSearchMenu = "openRecentSearchMenu"
        static let restorePreviousSearch = "restorePreviousSearch"
        static let tieResultsWindowToFindWindow = "tieResultsWindowToFindWindow"
        static let expandFoldersWhenShowingResults = "expandFoldersWhenShowingResults"
        static let showResultsEarly = "showResultsEarly"
        static let includeSpotlightResults = "includeSpotlightResults"
        static let quitWhenAllWindowsAreClosed = "quitWhenAllWindowsAreClosed"
        static let generalPreferences = "generalPreferences.v1"
        static let searchExecutionPreferences = "searchExecutionPreferences.v1"
        static let appearancePreferences = "appearancePreferences.v1"
        static let updatePreferences = "updatePreferences.v1"
    }

    static let shared = AppSettings(storage: MMKVKeyValueStore.shared)

    /// 结果列表字体大小或隐藏项淡化颜色变化时发出
    static let resultsAppearanceDidChangeNotification = Notification.Name("FileHound.AppSettings.resultsAppearanceDidChange")

    private let storage: KeyValueStoring

    init(storage: KeyValueStoring = MMKVKeyValueStore.shared) {
        self.storage = storage
    }

    var preferredTheme: AppTheme {
        get { rawPreferredTheme }
        set {
            storage.set(newValue.rawValue, forKey: Keys.preferredTheme)
            synchronizeAppearancePreferences()
        }
    }

    var preferredLanguage: AppLanguage {
        get { rawPreferredLanguage }
        set {
            storage.set(newValue.rawValue, forKey: Keys.preferredLanguage)
            synchronizeAppearancePreferences()
        }
    }

    var updateCheckPolicy: UpdateCheckPolicy {
        get { rawUpdateCheckPolicy }
        set {
            storage.set(newValue.rawValue, forKey: Keys.updateCheckPolicy)
            synchronizeUpdatePreferences()
        }
    }

    var resultsFontSize: Int {
        get { rawResultsFontSize }
        set {
            storage.set(String(newValue), forKey: Keys.resultsFontSize)
            synchronizeAppearancePreferences()
            NotificationCenter.default.post(name: Self.resultsAppearanceDidChangeNotification, object: self)
        }
    }

    var dimColorHex: String {
        get { rawDimColorHex }
        set {
            storage.set(newValue, forKey: Keys.dimColorHex)
            synchronizeAppearancePreferences()
            NotificationCenter.default.post(name: Self.resultsAppearanceDidChangeNotification, object: self)
        }
    }

    var autoDownloadUpdates: Bool {
        get { rawAutoDownloadUpdates }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.autoDownloadUpdates)
            synchronizeUpdatePreferences()
        }
    }

    var launchShortcut: String {
        get { storage.string(forKey: Keys.launchShortcut) ?? "" }
        set {
            storage.set(newValue, forKey: Keys.launchShortcut)
            synchronizeGeneralPreferences()
        }
    }

    var activationMode: SearchActivationMode {
        get {
            SearchActivationMode(rawValue: storage.string(forKey: Keys.activationMode) ?? SearchActivationMode.global.rawValue) ?? .global
        }
        set {
            storage.set(newValue.rawValue, forKey: Keys.activationMode)
            synchronizeGeneralPreferences()
        }
    }

    var openRecentSearchMenu: Bool {
        get { rawOpenRecentSearchMenu }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.openRecentSearchMenu)
            synchronizeGeneralPreferences()
        }
    }

    var restorePreviousSearch: Bool {
        get { rawRestorePreviousSearch }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.restorePreviousSearch)
            synchronizeGeneralPreferences()
        }
    }

    var tieResultsWindowToFindWindow: Bool {
        get { rawTieResultsWindowToFindWindow }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.tieResultsWindowToFindWindow)
            synchronizeGeneralPreferences()
        }
    }

    var expandFoldersWhenShowingResults: Bool {
        get { rawExpandFoldersWhenShowingResults }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.expandFoldersWhenShowingResults)
            synchronizeSearchExecutionPreferences()
        }
    }

    var showResultsEarly: Bool {
        get { rawShowResultsEarly }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.showResultsEarly)
            synchronizeSearchExecutionPreferences()
        }
    }

    var includeSpotlightResults: Bool {
        get { rawIncludeSpotlightResults }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.includeSpotlightResults)
            synchronizeSearchExecutionPreferences()
        }
    }

    var quitWhenAllWindowsAreClosed: Bool {
        get { rawQuitWhenAllWindowsAreClosed }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.quitWhenAllWindowsAreClosed)
            synchronizeGeneralPreferences()
        }
    }

    var generalPreferences: GeneralSearchPreferences {
        get {
            (try? storage.codableValue(GeneralSearchPreferences.self, forKey: Keys.generalPreferences))
                ?? GeneralSearchPreferences(
                    launchShortcut: launchShortcut,
                    activationMode: activationMode,
                    openRecentSearchMenu: openRecentSearchMenu,
                    restorePreviousSearch: restorePreviousSearch,
                    tieResultsWindowToFindWindow: tieResultsWindowToFindWindow,
                    quitWhenAllWindowsAreClosed: quitWhenAllWindowsAreClosed
                )
        }
        set {
            storage.set(newValue.launchShortcut, forKey: Keys.launchShortcut)
            storage.set(newValue.activationMode.rawValue, forKey: Keys.activationMode)
            storage.set(newValue.openRecentSearchMenu ? "true" : "false", forKey: Keys.openRecentSearchMenu)
            storage.set(newValue.restorePreviousSearch ? "true" : "false", forKey: Keys.restorePreviousSearch)
            storage.set(newValue.tieResultsWindowToFindWindow ? "true" : "false", forKey: Keys.tieResultsWindowToFindWindow)
            storage.set(newValue.quitWhenAllWindowsAreClosed ? "true" : "false", forKey: Keys.quitWhenAllWindowsAreClosed)
            try? storage.setCodable(newValue, forKey: Keys.generalPreferences)
        }
    }

    var searchExecutionPreferences: SearchExecutionPreferences {
        get {
            (try? storage.codableValue(SearchExecutionPreferences.self, forKey: Keys.searchExecutionPreferences))
                ?? SearchExecutionPreferences(
                    expandFoldersWhenShowingResults: expandFoldersWhenShowingResults,
                    showResultsEarly: showResultsEarly,
                    includeSpotlightResults: includeSpotlightResults
                )
        }
        set {
            storage.set(newValue.expandFoldersWhenShowingResults ? "true" : "false", forKey: Keys.expandFoldersWhenShowingResults)
            storage.set(newValue.showResultsEarly ? "true" : "false", forKey: Keys.showResultsEarly)
            storage.set(newValue.includeSpotlightResults ? "true" : "false", forKey: Keys.includeSpotlightResults)
            try? storage.setCodable(newValue, forKey: Keys.searchExecutionPreferences)
        }
    }

    var appearancePreferences: AppearancePreferences {
        get {
            (try? storage.codableValue(AppearancePreferences.self, forKey: Keys.appearancePreferences))
                ?? AppearancePreferences(
                    preferredTheme: preferredTheme,
                    preferredLanguage: preferredLanguage,
                    resultsFontSize: resultsFontSize,
                    dimColorHex: dimColorHex
                )
        }
        set {
            storage.set(newValue.preferredTheme.rawValue, forKey: Keys.preferredTheme)
            storage.set(newValue.preferredLanguage.rawValue, forKey: Keys.preferredLanguage)
            storage.set(String(newValue.resultsFontSize), forKey: Keys.resultsFontSize)
            storage.set(newValue.dimColorHex, forKey: Keys.dimColorHex)
            try? storage.setCodable(newValue, forKey: Keys.appearancePreferences)
            NotificationCenter.default.post(name: Self.resultsAppearanceDidChangeNotification, object: self)
        }
    }

    var updatesPreferences: UpdatePreferences {
        get {
            (try? storage.codableValue(UpdatePreferences.self, forKey: Keys.updatePreferences))
                ?? UpdatePreferences(
                    updateCheckPolicy: updateCheckPolicy,
                    autoDownloadUpdates: autoDownloadUpdates
                )
        }
        set {
            storage.set(newValue.updateCheckPolicy.rawValue, forKey: Keys.updateCheckPolicy)
            storage.set(newValue.autoDownloadUpdates ? "true" : "false", forKey: Keys.autoDownloadUpdates)
            try? storage.setCodable(newValue, forKey: Keys.updatePreferences)
        }
    }

    private var rawPreferredTheme: AppTheme {
        AppTheme(rawValue: storage.string(forKey: Keys.preferredTheme) ?? AppTheme.system.rawValue) ?? .system
    }

    private var rawPreferredLanguage: AppLanguage {
        AppLanguage(rawValue: storage.string(forKey: Keys.preferredLanguage) ?? AppLanguage.system.rawValue) ?? .system
    }

    private var rawUpdateCheckPolicy: UpdateCheckPolicy {
        UpdateCheckPolicy(rawValue: storage.string(forKey: Keys.updateCheckPolicy) ?? UpdateCheckPolicy.onLaunch.rawValue) ?? .onLaunch
    }

    private var rawResultsFontSize: Int {
        Int(storage.string(forKey: Keys.resultsFontSize) ?? "13") ?? 13
    }

    private var rawDimColorHex: String {
        storage.string(forKey: Keys.dimColorHex) ?? "#A0A7B3"
    }

    private var rawAutoDownloadUpdates: Bool {
        storage.string(forKey: Keys.autoDownloadUpdates) == "true"
    }

    private var rawOpenRecentSearchMenu: Bool {
        storage.string(forKey: Keys.openRecentSearchMenu) != "false"
    }

    private var rawRestorePreviousSearch: Bool {
        storage.string(forKey: Keys.restorePreviousSearch) == "true"
    }

    private var rawTieResultsWindowToFindWindow: Bool {
        storage.string(forKey: Keys.tieResultsWindowToFindWindow) != "false"
    }

    private var rawExpandFoldersWhenShowingResults: Bool {
        storage.string(forKey: Keys.expandFoldersWhenShowingResults) == "true"
    }

    private var rawShowResultsEarly: Bool {
        storage.string(forKey: Keys.showResultsEarly) != "false"
    }

    private var rawIncludeSpotlightResults: Bool {
        storage.string(forKey: Keys.includeSpotlightResults) != "false"
    }

    private var rawQuitWhenAllWindowsAreClosed: Bool {
        storage.string(forKey: Keys.quitWhenAllWindowsAreClosed) != "false"
    }

    private func synchronizeGeneralPreferences() {
        try? storage.setCodable(
            GeneralSearchPreferences(
                launchShortcut: launchShortcut,
                activationMode: activationMode,
                openRecentSearchMenu: openRecentSearchMenu,
                restorePreviousSearch: restorePreviousSearch,
                tieResultsWindowToFindWindow: tieResultsWindowToFindWindow,
                quitWhenAllWindowsAreClosed: quitWhenAllWindowsAreClosed
            ),
            forKey: Keys.generalPreferences
        )
    }

    private func synchronizeSearchExecutionPreferences() {
        try? storage.setCodable(
            SearchExecutionPreferences(
                expandFoldersWhenShowingResults: expandFoldersWhenShowingResults,
                showResultsEarly: showResultsEarly,
                includeSpotlightResults: includeSpotlightResults
            ),
            forKey: Keys.searchExecutionPreferences
        )
    }

    private func synchronizeAppearancePreferences() {
        try? storage.setCodable(
            AppearancePreferences(
                preferredTheme: preferredTheme,
                preferredLanguage: preferredLanguage,
                resultsFontSize: resultsFontSize,
                dimColorHex: dimColorHex
            ),
            forKey: Keys.appearancePreferences
        )
    }

    private func synchronizeUpdatePreferences() {
        try? storage.setCodable(
            UpdatePreferences(
                updateCheckPolicy: updateCheckPolicy,
                autoDownloadUpdates: autoDownloadUpdates
            ),
            forKey: Keys.updatePreferences
        )
    }
}
