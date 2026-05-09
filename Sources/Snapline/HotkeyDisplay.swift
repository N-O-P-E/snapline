import AppKit
import Carbon.HIToolbox

/// Format a `HotkeyBinding` into the conventional symbol form (e.g. "⌘⇧9", "⌃⌥F1").
enum HotkeyDisplay {
    static func format(_ b: HotkeyBinding) -> String {
        guard b.keyCode != 0 else { return "Not set" }
        var s = ""
        if b.modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if b.modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if b.modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if b.modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyName(for: b.keyCode)
        return s
    }

    /// Map a Carbon virtual key code to a human-readable label. Special keys
    /// get glyphs (↩ ⎋ ⇥ etc.); regular ANSI keys are translated through the
    /// active keyboard layout via UCKeyTranslate.
    static func keyName(for keyCode: UInt32) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        return uckTranslate(keyCode: keyCode) ?? "?"
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return:        "↩",
        kVK_Tab:           "⇥",
        kVK_Space:         "Space",
        kVK_Delete:        "⌫",
        kVK_Escape:        "⎋",
        kVK_LeftArrow:     "←",
        kVK_RightArrow:    "→",
        kVK_DownArrow:     "↓",
        kVK_UpArrow:       "↑",
        kVK_F1:  "F1",  kVK_F2:  "F2",  kVK_F3:  "F3",  kVK_F4:  "F4",
        kVK_F5:  "F5",  kVK_F6:  "F6",  kVK_F7:  "F7",  kVK_F8:  "F8",
        kVK_F9:  "F9",  kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_Home:          "↖",
        kVK_End:           "↘",
        kVK_PageUp:        "⇞",
        kVK_PageDown:      "⇟",
        kVK_ForwardDelete: "⌦",
    ]

    private static func uckTranslate(keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }

        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyLayoutPtr = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeys: UInt32 = 0
        var actualLength: Int = 0
        var chars: [UniChar] = [0, 0, 0, 0]

        let status = UCKeyTranslate(
            keyLayoutPtr,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeys,
            chars.count,
            &actualLength,
            &chars
        )
        guard status == noErr, actualLength > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: actualLength).uppercased()
    }
}

/// Convert NSEvent modifier flags into Carbon modifier mask.
enum CarbonModifiers {
    static func mask(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }
}
