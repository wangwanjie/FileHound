import AppKit

extension NSColor {
    func fhResolvedColor(for appearance: NSAppearance) -> NSColor {
        var resolved = self
        appearance.performAsCurrentDrawingAppearance {
            if let cgColor = self.cgColor.copy(alpha: 1), let color = NSColor(cgColor: cgColor) {
                resolved = color.usingColorSpace(.deviceRGB) ?? color
            } else {
                resolved = self.usingColorSpace(.deviceRGB) ?? self
            }
        }
        return resolved
    }

    func fhResolvedCGColor(for appearance: NSAppearance) -> CGColor {
        fhResolvedColor(for: appearance).cgColor
    }

    #if DEBUG
    func fhResolvedHex(for appearanceName: NSAppearance.Name) -> String {
        let appearance = NSAppearance(named: appearanceName) ?? NSApp.effectiveAppearance
        let resolved = fhResolvedColor(for: appearance).usingColorSpace(.deviceRGB) ?? self
        let red = Int(round(resolved.redComponent * 255))
        let green = Int(round(resolved.greenComponent * 255))
        let blue = Int(round(resolved.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
    #endif
}

extension NSAppearance {
    var fhIsDarkMode: Bool {
        let match = bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        return match == .darkAqua || match == .vibrantDark
    }
}

extension NSColor {
    static func fhWindowSurface(for appearance: NSAppearance, alpha: CGFloat = 1) -> NSColor {
        let white: CGFloat = appearance.fhIsDarkMode ? 0.12 : 0.97
        return NSColor(calibratedWhite: white, alpha: alpha)
    }

    static func fhPanelSurface(for appearance: NSAppearance, alpha: CGFloat = 1) -> NSColor {
        let white: CGFloat = appearance.fhIsDarkMode ? 0.17 : 0.94
        return NSColor(calibratedWhite: white, alpha: alpha)
    }

    static func fhCardSurface(for appearance: NSAppearance, alpha: CGFloat = 1) -> NSColor {
        let white: CGFloat = appearance.fhIsDarkMode ? 0.19 : 0.965
        return NSColor(calibratedWhite: white, alpha: alpha)
    }

    static func fhHairline(for appearance: NSAppearance, alpha: CGFloat = 1) -> NSColor {
        let white: CGFloat = appearance.fhIsDarkMode ? 0.30 : 0.82
        return NSColor(calibratedWhite: white, alpha: alpha)
    }
}

final class AppearanceAwareView: NSView {
    var backgroundColorProvider: ((NSAppearance) -> NSColor)? {
        didSet {
            applyBackgroundAppearance()
        }
    }
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackgroundAppearance()
        onAppearanceChange?()
    }

    func applyBackgroundAppearance() {
        wantsLayer = true
        guard let backgroundColorProvider else {
            return
        }
        layer?.backgroundColor = backgroundColorProvider(effectiveAppearance).fhResolvedCGColor(for: effectiveAppearance)
    }
}

extension NSColor {
    convenience init?(hexString: String) {
        let hex = hexString.replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String? {
        // 已是 RGB 颜色时直接取分量，避免跨色彩空间转换导致十六进制值漂移
        let color: NSColor
        if type == .componentBased, colorSpace.colorSpaceModel == .rgb {
            color = self
        } else if let converted = usingColorSpace(.sRGB) {
            color = converted
        } else {
            return nil
        }
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
