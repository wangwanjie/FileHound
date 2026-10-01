import AppKit
import SnapKit

final class PermissionsPreferencesViewController: NSViewController {
    private let coordinator: PermissionGuidanceCoordinator
    private let openSettings: (URL) -> Void
    private let fullDiskAccessLabel = NSTextField(labelWithString: L10n.string("preferences.permissions.fda.label"))
    private let fullDiskAccessValue = NSTextField(labelWithString: "")
    private let helperLabel = NSTextField(labelWithString: L10n.string("preferences.permissions.helper.label"))
    private let helperValue = NSTextField(labelWithString: "")
    private let explanationLabel = NSTextField(wrappingLabelWithString: L10n.string("preferences.permissions.fda.explanation"))
    private let openSettingsButton = NSButton(title: L10n.string("preferences.permissions.open_settings"), target: nil, action: nil)
    private let refreshButton = NSButton(title: L10n.string("preferences.permissions.refresh"), target: nil, action: nil)
    private(set) var state: PermissionState?

    init(
        coordinator: PermissionGuidanceCoordinator = PermissionGuidanceCoordinator(),
        openSettings: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.coordinator = coordinator
        self.openSettings = openSettings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.permissions.title"),
            subtitle: L10n.string("preferences.permissions.subtitle")
        )

        explanationLabel.textColor = .secondaryLabelColor
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.target = self
        openSettingsButton.action = #selector(openFullDiskAccessSettings(_:))
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refresh(_:))

        let grid = NSGridView(views: [
            [fullDiskAccessLabel, fullDiskAccessValue],
            [helperLabel, helperValue]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing

        let buttons = NSStackView(views: [openSettingsButton, refreshButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [grid, explanationLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14

        rootView.contentGuide.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.top.trailing.equalToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
        }
        explanationLabel.snp.makeConstraints { make in
            make.width.lessThanOrEqualTo(stack)
        }

        view = rootView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        reloadState()
    }

    func reloadState() {
        let state = coordinator.currentState()
        self.state = state
        fullDiskAccessValue.stringValue = state.fullDiskAccessText
        fullDiskAccessValue.textColor = state.fullDiskAccessGranted ? .systemGreen : .systemOrange
        helperValue.stringValue = state.helperText
        helperValue.textColor = .secondaryLabelColor
        explanationLabel.isHidden = state.fullDiskAccessGranted
    }

    @objc
    private func applicationDidBecomeActive(_ notification: Notification) {
        // 用户从系统设置授权后回到 App 时自动刷新
        reloadState()
    }

    @objc
    func refresh(_ sender: Any?) {
        reloadState()
    }

    @objc
    func openFullDiskAccessSettings(_ sender: Any?) {
        openSettings(PermissionGuidanceCoordinator.fullDiskAccessSettingsURL)
    }

    #if DEBUG
    var debugFullDiskAccessText: String { fullDiskAccessValue.stringValue }
    var debugExplanationHidden: Bool { explanationLabel.isHidden }
    #endif
}
