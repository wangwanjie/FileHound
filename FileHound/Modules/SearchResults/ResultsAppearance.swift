import AppKit

/// 结果视图的字体大小与隐藏项淡化颜色，来自外观偏好
struct ResultsAppearance: Equatable {
    static let minimumFontSize: CGFloat = 9
    static let maximumFontSize: CGFloat = 24

    let fontSize: CGFloat
    let dimColor: NSColor

    init(fontSize: Int, dimColorHex: String) {
        self.fontSize = min(max(CGFloat(fontSize), Self.minimumFontSize), Self.maximumFontSize)
        dimColor = NSColor(hexString: dimColorHex) ?? .tertiaryLabelColor
    }

    static func current(settings: AppSettings = .shared) -> ResultsAppearance {
        ResultsAppearance(fontSize: settings.resultsFontSize, dimColorHex: settings.dimColorHex)
    }

    var font: NSFont {
        .systemFont(ofSize: fontSize, weight: .regular)
    }

    /// 默认 13pt 对应 24pt 行高，随字号等量增减
    var rowHeight: CGFloat {
        ceil(fontSize) + 11
    }

    func textColor(for item: SearchResultItem, baseColor: NSColor = .labelColor) -> NSColor {
        item.isInvisible ? dimColor : baseColor
    }
}
