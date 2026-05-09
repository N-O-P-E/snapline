import Foundation
import Carbon.HIToolbox

enum Settings {
    private static let key = "TargetBundleIdentifier"

    static var targetBundleID: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private static let onboardingKey = "HasCompletedOnboarding"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingKey) }
    }

    // MARK: Paste shortcut

    enum PasteShortcut: String, CaseIterable {
        case auto         // ⌃V for known terminals, ⌘V for everything else
        case commandV
        case controlV

        var label: String {
            switch self {
            case .auto:     return "Auto"
            case .commandV: return "Always ⌘V"
            case .controlV: return "Always ⌃V"
            }
        }
    }

    private static let pasteShortcutKey = "PasteShortcut"

    static var pasteShortcut: PasteShortcut {
        get {
            if let raw = UserDefaults.standard.string(forKey: pasteShortcutKey),
               let v = PasteShortcut(rawValue: raw) { return v }
            return .auto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: pasteShortcutKey) }
    }

    /// Bundle IDs of terminal emulators where Claude Code's TUI listens for ⌃V.
    static let terminalBundleIDs: Set<String> = [
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.apple.Terminal",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "co.zeit.hyper",
        "org.tabby",
        "com.github.wez.wezterm",
    ]

    // MARK: Hotkeys

    static let defaultSingleShot = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_9),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let defaultMultiShot = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_9),
        modifiers: UInt32(cmdKey | shiftKey | optionKey)
    )

    private static let singleHotkeyKey = "SingleShotHotkey"
    private static let multiHotkeyKey  = "MultiShotHotkey"

    static var singleShotHotkey: HotkeyBinding {
        get { HotkeyBinding.load(forKey: singleHotkeyKey) ?? defaultSingleShot }
        set { newValue.save(forKey: singleHotkeyKey) }
    }

    static var multiShotHotkey: HotkeyBinding {
        get { HotkeyBinding.load(forKey: multiHotkeyKey) ?? defaultMultiShot }
        set { newValue.save(forKey: multiHotkeyKey) }
    }
}

// MARK: - HotkeyBinding

struct HotkeyBinding: Equatable {
    /// Carbon virtual key code (e.g. kVK_ANSI_9).
    var keyCode: UInt32
    /// Carbon modifier mask: cmdKey | shiftKey | optionKey | controlKey.
    var modifiers: UInt32

    /// Posted to UserDefaults whenever bindings change so the HotkeyManager
    /// can re-register without polling.
    static let didChangeNotification = Notification.Name("Snapline.HotkeysDidChange")

    func save(forKey key: String) {
        UserDefaults.standard.set([
            "keyCode": Int(keyCode),
            "modifiers": Int(modifiers),
        ], forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    static func load(forKey key: String) -> HotkeyBinding? {
        guard let dict = UserDefaults.standard.dictionary(forKey: key),
              let kc = dict["keyCode"] as? Int,
              let mods = dict["modifiers"] as? Int
        else { return nil }
        return HotkeyBinding(keyCode: UInt32(kc), modifiers: UInt32(mods))
    }
}
