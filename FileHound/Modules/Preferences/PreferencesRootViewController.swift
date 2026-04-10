import AppKit
import SnapKit

final class PreferencesRootViewController: NSViewController {
    private let initialSegment: Int
    private lazy var segmentedControl = NSSegmentedControl(
        labels: [
            L10n.string("preferences.tab.general"),
            L10n.string("preferences.tab.search"),
            L10n.string("preferences.tab.appearance"),
            L10n.string("preferences.tab.update")
        ],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let contentContainer = NSView()

    private lazy var contentControllers: [NSViewController] = [
        GeneralPreferencesViewController(),
        SearchPreferencesViewController(),
        AppearancePreferencesViewController(),
        UpdatePreferencesViewController()
    ]

    init(initialSegment: Int = 2) {
        self.initialSegment = initialSegment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var selectedSegmentIndex: Int {
        segmentedControl.selectedSegment
    }

    override func loadView() {
        let rootView = NSView()

        segmentedControl.setAccessibilityIdentifier("PreferencesSegments")
        segmentedControl.setAccessibilityLabel("PreferencesSegments")
        segmentedControl.selectedSegment = initialSegment
        segmentedControl.target = self
        segmentedControl.action = #selector(segmentChanged)

        rootView.addSubview(segmentedControl)
        rootView.addSubview(contentContainer)

        segmentedControl.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(20)
        }
        contentContainer.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview().inset(20)
            make.top.equalTo(segmentedControl.snp.bottom).offset(16)
            make.width.equalTo(PreferencesLayout.contentWidth)
            make.trailing.lessThanOrEqualToSuperview().inset(20)
        }

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        renderSelectedController(animated: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshWindowSize(animated: false)
    }

    @objc
    private func segmentChanged() {
        renderSelectedController(animated: true)
    }

    func refreshWindowSize(animated: Bool) {
        guard let window = view.window else {
            return
        }

        let targetHeight = min(
            max(measuredContentHeight() + 86, PreferencesLayout.minWindowHeight),
            PreferencesLayout.maxWindowHeight
        )

        let targetContentSize = NSSize(width: PreferencesLayout.windowWidth, height: targetHeight)
        let targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize))
        let origin = NSPoint(x: window.frame.origin.x, y: window.frame.maxY - targetFrame.height)
        window.setFrame(NSRect(origin: origin, size: targetFrame.size), display: true, animate: animated)
    }

    private func renderSelectedController(animated: Bool) {
        let controller = contentControllers[segmentedControl.selectedSegment]
        let contentView = controller.view
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        contentContainer.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        view.layoutSubtreeIfNeeded()
        refreshWindowSize(animated: animated)
    }

    private func measuredContentHeight() -> CGFloat {
        let controller = contentControllers[segmentedControl.selectedSegment]
        controller.view.layoutSubtreeIfNeeded()
        return max(controller.view.fittingSize.height, 220)
    }
}
