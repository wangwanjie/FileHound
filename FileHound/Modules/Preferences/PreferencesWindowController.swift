import AppKit
import SnapKit

final class PreferencesWindowController: NSWindowController {
    private lazy var tabButtons = [
        makeTabButton(title: L10n.string("preferences.tab.appearance")),
        makeTabButton(title: L10n.string("preferences.tab.search")),
        makeTabButton(title: L10n.string("preferences.tab.update")),
        makeTabButton(title: L10n.string("preferences.tab.permissions"))
    ]

    private lazy var contentControllers: [NSViewController] = [
        AppearancePreferencesViewController(),
        SearchPreferencesViewController(),
        UpdatePreferencesViewController(),
        PermissionsPreferencesViewController()
    ]

    private let contentContainer = NSView()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.string("preferences.window.title")
        window.center()
        self.init(window: window)
        setupWindow()
    }

    private func makeTabButton(title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        return button
    }

    private func setupWindow() {
        guard let window else { return }

        let rootView = NSView()
        let buttonStack = NSStackView(views: tabButtons)
        buttonStack.orientation = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8

        rootView.addSubview(buttonStack)
        rootView.addSubview(contentContainer)

        buttonStack.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview().inset(20)
        }
        contentContainer.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(20)
            make.top.equalTo(buttonStack.snp.bottom).offset(16)
        }

        window.contentView = rootView

        for (index, button) in tabButtons.enumerated() {
            button.target = self
            button.action = #selector(selectTab(_:))
            button.tag = index
        }

        renderTab(at: 0)
    }

    @objc
    private func selectTab(_ sender: NSButton) {
        renderTab(at: sender.tag)
    }

    private func renderTab(at index: Int) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }

        let controller = contentControllers[index]
        let contentView = controller.view
        contentContainer.addSubview(contentView)

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}

final class PreferencesSectionView: NSView {
    let contentGuide = NSView()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.textColor = .secondaryLabelColor

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(contentGuide)

        titleLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview()
        }
        subtitleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
        }
        contentGuide.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(subtitleLabel.snp.bottom).offset(20)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
