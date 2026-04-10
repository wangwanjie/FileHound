import AppKit

final class PreferencesWindowController: NSWindowController {
    convenience init() {
        let rootViewController = PreferencesRootViewController()
        let window = NSWindow(contentViewController: rootViewController)
        window.setContentSize(NSSize(width: PreferencesLayout.windowWidth, height: PreferencesLayout.minWindowHeight))
        window.title = L10n.string("preferences.window.title")
        window.center()
        window.styleMask = [.titled, .closable, .miniaturizable]
        self.init(window: window)
        window.styleMask.remove(.resizable)
    }

    func show(segment initialSegment: Int? = nil, sender: Any? = nil) {
        if let initialSegment {
            installRootViewController(initialSegment: initialSegment)
        } else if window?.contentViewController == nil {
            installRootViewController(initialSegment: 0)
        }

        showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        (window?.contentViewController as? PreferencesRootViewController)?.refreshWindowSize(animated: false)
    }

    func reloadLocalizedContent() {
        guard window != nil else {
            return
        }

        installRootViewController(initialSegment: selectedSegmentIndex)
        (window?.contentViewController as? PreferencesRootViewController)?.refreshWindowSize(animated: false)
    }

    private var selectedSegmentIndex: Int {
        (window?.contentViewController as? PreferencesRootViewController)?.selectedSegmentIndex ?? 0
    }

    private func installRootViewController(initialSegment: Int) {
        let rootViewController = PreferencesRootViewController(initialSegment: initialSegment)

        if let window {
            window.contentViewController = rootViewController
            window.title = L10n.string("preferences.window.title")
            return
        }

        let window = NSWindow(contentViewController: rootViewController)
        window.setContentSize(NSSize(width: PreferencesLayout.windowWidth, height: PreferencesLayout.minWindowHeight))
        window.title = L10n.string("preferences.window.title")
        window.center()
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.styleMask.remove(.resizable)
        self.window = window
    }
}

final class PreferencesSectionView: NSView {
    let contentGuide = NSView()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)

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
            make.leading.bottom.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
            make.top.equalTo(subtitleLabel.snp.bottom).offset(20)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
