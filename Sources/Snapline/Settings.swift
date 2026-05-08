import Foundation

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
}
