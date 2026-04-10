import AppKit
import SnapKit

final class ResultsToolbarView: NSView {
    let gridButton = ResultsToolbarButton(symbolName: "square.grid.2x2", accessibilityID: "ResultsModeGridButton")
    let tableButton = ResultsToolbarButton(symbolName: "list.bullet.rectangle", accessibilityID: "ResultsModeTableButton")
    let treeButton = ResultsToolbarButton(symbolName: "list.bullet.indent", accessibilityID: "ResultsModeTreeButton")
    let invisiblesButton = ResultsToolbarToggleButton(symbolName: "eye.slash", accessibilityID: "ResultsShowInvisiblesButton")
    let packageButton = ResultsToolbarToggleButton(symbolName: "shippingbox", accessibilityID: "ResultsShowPackagesButton")
    let trashedButton = ResultsToolbarToggleButton(symbolName: "trash", accessibilityID: "ResultsShowTrashedButton")
    let filterField = NSSearchField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        filterField.setAccessibilityIdentifier("ResultsFilterField")
        filterField.placeholderString = "Filter"

        let modeGroup = makeGroupedStack(title: "View", views: [gridButton, tableButton, treeButton])
        let optionsGroup = makeGroupedStack(title: "Show", views: [invisiblesButton, packageButton, trashedButton])
        let filterGroup = makeGroupedStack(title: nil, views: [filterField])

        let stack = NSStackView(views: [filterGroup, NSView(), modeGroup, optionsGroup])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 18

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor

        addSubview(stack)

        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(10)
        }

        filterField.snp.makeConstraints { make in
            make.width.equalTo(260)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeGroupedStack(title: String?, views: [NSView]) -> NSView {
        let container = NSView()
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        container.addSubview(stack)

        if let title {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            container.addSubview(label)
            label.snp.makeConstraints { make in
                make.leading.top.equalToSuperview()
            }
            stack.snp.makeConstraints { make in
                make.leading.equalToSuperview()
                make.top.equalTo(label.snp.bottom).offset(4)
                make.trailing.bottom.equalToSuperview()
            }
            return container
        }

        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        return container
    }
}

final class ResultsToolbarButton: NSButton {
    init(symbolName: String, accessibilityID: String) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityID)
        bezelStyle = .texturedRounded
        imagePosition = .imageOnly
        setButtonType(.momentaryPushIn)
        contentTintColor = .secondaryLabelColor
        focusRingType = .none
        setAccessibilityIdentifier(accessibilityID)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ResultsToolbarToggleButton: NSButton {
    init(symbolName: String, accessibilityID: String) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityID)
        bezelStyle = .texturedRounded
        imagePosition = .imageOnly
        setButtonType(.toggle)
        contentTintColor = .secondaryLabelColor
        focusRingType = .none
        setAccessibilityIdentifier(accessibilityID)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
