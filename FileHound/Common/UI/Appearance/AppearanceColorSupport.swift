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
