import AppKit

final class PreferencesWindowController: NSWindowController {
    convenience init() {
        let rootViewController = PreferencesRootViewController()
        let window = NSWindow(contentViewController: rootViewController)
        window.setContentSize(NSSize(width: 760, height: 560))
        window.title = L10n.string("preferences.window.title")
        window.center()
        window.styleMask = [.titled, .closable, .miniaturizable]
        self.init(window: window)
        window.styleMask.remove(.resizable)
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
