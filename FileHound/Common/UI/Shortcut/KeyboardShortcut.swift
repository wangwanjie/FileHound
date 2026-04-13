import AppKit
import SnapKit

struct KeyboardShortcut: Equatable, Sendable {
    let keyCode: UInt16
    let modifierFlags: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags.intersection([.command, .control, .option, .shift])
    }

    init?(serialized: String) {
        let trimmed = serialized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty == false else {
            return nil
        }

        let parts = trimmed
            .split(whereSeparator: { $0 == "-" || $0 == "+" })
            .map(String.init)
        guard let keyToken = parts.last, let keyCode = Self.keyCodeByToken[keyToken] else {
            return nil
        }

        var modifierFlags = NSEvent.ModifierFlags()
        for token in parts.dropLast() {
            switch token {
            case "cmd", "command":
                modifierFlags.insert(.command)
            case "ctrl", "control":
                modifierFlags.insert(.control)
            case "opt", "alt", "option":
                modifierFlags.insert(.option)
            case "shift":
                modifierFlags.insert(.shift)
            default:
                return nil
            }
        }

        let normalizedFlags = modifierFlags.intersection([.command, .control, .option, .shift])
        guard normalizedFlags.isEmpty == false else {
            return nil
        }

        self.init(keyCode: keyCode, modifierFlags: normalizedFlags)
    }

    var serialized: String {
        var tokens: [String] = []
        if modifierFlags.contains(.command) {
            tokens.append("cmd")
        }
        if modifierFlags.contains(.control) {
            tokens.append("ctrl")
        }
        if modifierFlags.contains(.option) {
            tokens.append("opt")
        }
        if modifierFlags.contains(.shift) {
            tokens.append("shift")
        }
        tokens.append(Self.keyToken(for: keyCode))
        return tokens.joined(separator: "-")
    }

    var displayString: String {
        var value = ""
        if modifierFlags.contains(.command) {
            value += "\u{2318}"
        }
        if modifierFlags.contains(.control) {
            value += "\u{2303}"
        }
        if modifierFlags.contains(.option) {
            value += "\u{2325}"
        }
        if modifierFlags.contains(.shift) {
            value += "\u{21E7}"
        }
        value += Self.displayToken(for: keyCode)
        return value
    }

    static func capture(from event: NSEvent) -> KeyboardShortcut? {
        let shortcut = KeyboardShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        guard shortcut.hasPrimaryModifier, keyCodeByToken.values.contains(shortcut.keyCode) else {
            return nil
        }
        return shortcut
    }

    private var hasPrimaryModifier: Bool {
        modifierFlags.intersection([.command, .control, .option]).isEmpty == false
    }

    private static func keyToken(for keyCode: UInt16) -> String {
        tokenByKeyCode[keyCode] ?? "space"
    }

    private static func displayToken(for keyCode: UInt16) -> String {
        displayByKeyCode[keyCode] ?? "Space"
    }

    private static let orderedKeyEntries: [(token: String, keyCode: UInt16, display: String)] = [
        ("a", 0, "A"), ("s", 1, "S"), ("d", 2, "D"), ("f", 3, "F"), ("h", 4, "H"),
        ("g", 5, "G"), ("z", 6, "Z"), ("x", 7, "X"), ("c", 8, "C"), ("v", 9, "V"),
        ("b", 11, "B"), ("q", 12, "Q"), ("w", 13, "W"), ("e", 14, "E"), ("r", 15, "R"),
        ("y", 16, "Y"), ("t", 17, "T"), ("1", 18, "1"), ("2", 19, "2"), ("3", 20, "3"),
        ("4", 21, "4"), ("6", 22, "6"), ("5", 23, "5"), ("9", 25, "9"), ("7", 26, "7"),
        ("8", 28, "8"), ("0", 29, "0"), ("o", 31, "O"), ("u", 32, "U"), ("i", 34, "I"),
        ("p", 35, "P"), ("l", 37, "L"), ("j", 38, "J"), ("k", 40, "K"), ("n", 45, "N"),
        ("m", 46, "M"), ("space", 49, "Space"), ("return", 36, "Return"), ("tab", 48, "Tab"),
        ("delete", 51, "Delete"), ("escape", 53, "Esc"), ("left", 123, "\u{2190}"),
        ("right", 124, "\u{2192}"), ("down", 125, "\u{2193}"), ("up", 126, "\u{2191}")
    ]

    private static let keyCodeByToken = Dictionary(uniqueKeysWithValues: orderedKeyEntries.map { ($0.token, $0.keyCode) })
    private static let tokenByKeyCode = Dictionary(uniqueKeysWithValues: orderedKeyEntries.map { ($0.keyCode, $0.token) })
    private static let displayByKeyCode = Dictionary(uniqueKeysWithValues: orderedKeyEntries.map { ($0.keyCode, $0.display) })
}

final class ShortcutRecorderField: NSControl {
    private let label = NSTextField(labelWithString: "")
    private var isFocused = false {
        didSet {
            updateAppearance()
        }
    }

    var placeholderString: String? {
        didSet {
            updateDisplay()
        }
    }

    var shortcut: KeyboardShortcut? {
        didSet {
            updateDisplay()
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 180, height: 32)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1

        label.lineBreakMode = .byTruncatingTail
        label.alignment = .left
        addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
        }

        updateDisplay()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:
            shortcut = nil
            sendAction(action, to: target)
        case 53:
            _ = window?.makeFirstResponder(nil)
        default:
            guard let shortcut = KeyboardShortcut.capture(from: event) else {
                NSSound.beep()
                return
            }
            self.shortcut = shortcut
            sendAction(action, to: target)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        isFocused = didBecome
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        isFocused = false
        return didResign
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateDisplay() {
        label.stringValue = shortcut?.displayString ?? (placeholderString ?? "")
        label.textColor = shortcut == nil ? .placeholderTextColor : .labelColor
        setAccessibilityValue(label.stringValue)
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.textBackgroundColor.fhResolvedCGColor(for: effectiveAppearance)
        layer?.borderColor = (isFocused ? NSColor.controlAccentColor : NSColor.separatorColor).fhResolvedCGColor(for: effectiveAppearance)
    }
}

#if DEBUG
extension ShortcutRecorderField {
    var debugDisplayedString: String {
        label.stringValue
    }
}
#endif
