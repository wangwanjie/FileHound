import AppKit
import SnapKit

final class PreferencesRootViewController: NSViewController {
    private let initialSegment: Int
    private let segmentedControl = NSSegmentedControl(
        labels: ["General", "Search", "Appearance", "Updates"],
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
            make.width.equalTo(480)
        }
        contentContainer.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(20)
            make.top.equalTo(segmentedControl.snp.bottom).offset(16)
        }

        view = rootView
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        renderSelectedController()
    }

    @objc
    private func segmentChanged() {
        renderSelectedController()
    }

    private func renderSelectedController() {
        let controller = contentControllers[segmentedControl.selectedSegment]
        let contentView = controller.view
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        contentContainer.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
