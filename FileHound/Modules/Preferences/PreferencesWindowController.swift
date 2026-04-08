import AppKit

final class PreferencesWindowController: NSWindowController {
    private let tabButtons = ["外观", "搜索", "更新", "权限"].map { title in
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        return button
    }

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
        window.title = "偏好设置"
        window.center()
        self.init(window: window)
        setupWindow()
    }

    private func setupWindow() {
        guard let window else { return }

        let rootView = NSView()
        let buttonStack = NSStackView(views: tabButtons)
        buttonStack.orientation = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(buttonStack)
        rootView.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            buttonStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            buttonStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20),

            contentContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            contentContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            contentContainer.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 16),
            contentContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -20)
        ])

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
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }
}

final class PreferencesSectionView: NSView {
    init(title: String, subtitle: String) {
        super.init(frame: .zero)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),

            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
