import AppKit
import SnapKit

final class SearchRuleListView: NSView {
    /// 行自身带有上下 padding，面板竖向 inset 加上行 padding 后与横向 inset 一致，四周视觉留白相同。
    static let horizontalInset: CGFloat = 14
    static let verticalInset: CGFloat = horizontalInset - SearchRuleRowView.Layout.verticalPadding

    let stackView = NSStackView()
    private let scrollView = NSScrollView()
    private let contentView = NSView()
    private(set) var logicSummary: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        setAccessibilityIdentifier("SearchRulesPanel")
        setAccessibilityElement(true)
        setAccessibilityLabel("SearchRulesPanel")
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.setAccessibilityIdentifier("SearchRulesScrollView")
        scrollView.setAccessibilityLabel("SearchRulesScrollView")
        scrollView.documentView = contentView
        contentView.setContentHuggingPriority(.required, for: .vertical)
        contentView.setContentCompressionResistancePriority(.required, for: .vertical)

        addSubview(scrollView)
        contentView.addSubview(stackView)

        scrollView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(Self.horizontalInset)
            make.top.bottom.equalToSuperview().inset(Self.verticalInset)
        }
        contentView.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(scrollView.contentView)
            make.width.equalTo(scrollView.contentView.snp.width)
            make.height.greaterThanOrEqualTo(scrollView.contentView.snp.height)
        }
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        applyAppearance()
    }

    var preferredContentHeight: CGFloat {
        layoutSubtreeIfNeeded()
        return stackView.fittingSize.height + Self.verticalInset * 2
    }

    func updateLogicSummary(_ text: String) {
        logicSummary = text
        setAccessibilityValue(text)
    }

    func setScrollingEnabled(_ enabled: Bool) {
        scrollView.hasVerticalScroller = enabled
        scrollView.verticalScrollElasticity = enabled ? .automatic : .none
        scrollView.setAccessibilityValue(enabled ? "scrolling" : "fitting")
        if enabled == false {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance(resolvedAgainst appearance: NSAppearance? = nil) {
        let resolvedAppearance = appearance ?? effectiveAppearance
        layer?.borderColor = NSColor.fhHairline(for: resolvedAppearance).fhResolvedCGColor(for: resolvedAppearance)
        layer?.backgroundColor = NSColor.fhPanelSurface(for: resolvedAppearance, alpha: 0.92).fhResolvedCGColor(for: resolvedAppearance)
    }
}

#if DEBUG
extension SearchRuleListView {
    var debugVisibleContentHeight: CGFloat {
        scrollView.contentView.bounds.height
    }

    var debugDocumentContentHeight: CGFloat {
        contentView.frame.height
    }

    func debugBackgroundHex(for appearanceName: NSAppearance.Name) -> String {
        let appearance = NSAppearance(named: appearanceName)
            ?? NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua)!
        return NSColor.fhPanelSurface(for: appearance, alpha: 0.92).fhResolvedHex(for: appearanceName)
    }
}
#endif
