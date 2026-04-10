import AppKit
import SnapKit

final class SearchRuleListView: NSView {
    let stackView = NSStackView()
    private let scrollView = NSScrollView()
    private let contentView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        setAccessibilityIdentifier("SearchRulesPanel")
        setAccessibilityElement(true)
        setAccessibilityLabel("SearchRulesPanel")
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.65).cgColor

        stackView.orientation = .vertical
        stackView.spacing = 10

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = contentView

        addSubview(scrollView)
        contentView.addSubview(stackView)

        scrollView.snp.makeConstraints { make in
            make.leading.top.trailing.equalToSuperview().inset(16)
        }
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.contentView)
        }
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        scrollView.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(16)
        }
    }

    var preferredContentHeight: CGFloat {
        layoutSubtreeIfNeeded()
        return stackView.fittingSize.height + 32
    }

    func setScrollingEnabled(_ enabled: Bool) {
        scrollView.hasVerticalScroller = enabled
        scrollView.verticalScrollElasticity = enabled ? .automatic : .none
        if enabled == false {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
