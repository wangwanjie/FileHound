import AppKit

/// 结果视图的字体大小与隐藏项淡化颜色，来自外观偏好
struct ResultsAppearance: Equatable {
    /// 与 Finder 列表视图的文字大小范围（10–16pt）保持一致，过大的字号会让文字与图标、表头比例失调
    static let minimumFontSize: CGFloat = 10
    static let maximumFontSize: CGFloat = 16

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

    /// 列表行图标随字号等比缩放，默认 13pt 对应 16pt 图标
    var listIconSize: CGFloat {
        max(16, round(fontSize * 16 / 13))
    }

    func textColor(for item: SearchResultItem, baseColor: NSColor = .labelColor) -> NSColor {
        item.isInvisible ? dimColor : baseColor
    }
}
