import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyManager()
    private let targetSubmenu = NSMenu()
    private var targetMenuItem: NSMenuItem!
    private let pasteSubmenu = NSMenu()
    private var pasteMenuItem: NSMenuItem!
    private var singleShotMenuItem: NSMenuItem!
    private var multiShotMenuItem: NSMenuItem!
    private var hotkeyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make(size: 18)
            button.image?.accessibilityDescription = "Snapline"
        }

        let menu = NSMenu()
        singleShotMenuItem = NSMenuItem(title: "", action: #selector(triggerSingle), keyEquivalent: "")
        multiShotMenuItem  = NSMenuItem(title: "", action: #selector(triggerMulti),  keyEquivalent: "")
        menu.addItem(singleShotMenuItem)
        menu.addItem(multiShotMenuItem)
        refreshHotkeyMenuTitles()

        targetMenuItem = NSMenuItem(title: "Target App", action: nil, keyEquivalent: "")
        targetMenuItem.submenu = targetSubmenu
        targetSubmenu.delegate = self
        menu.addItem(targetMenuItem)

        pasteMenuItem = NSMenuItem(title: "Paste Shortcut", action: nil, keyEquivalent: "")
        pasteMenuItem.submenu = pasteSubmenu
        pasteSubmenu.delegate = self
        menu.addItem(pasteMenuItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Setup…", action: #selector(showOnboarding), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        refreshTargetMenuTitle()
        refreshPasteMenuTitle()

        hotkey.onTrigger = { [weak self] action in
            switch action {
            case .singleShot: self?.runCapture(mode: .focus)
            case .multiShot:  CaptureAndPaste.runMultiShot()
            }
        }
        hotkey.register()

        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: HotkeyBinding.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // queue: .main means we're already on the main thread; this avoids
            // the Swift-6 strict-concurrency error from spawning a Task that
            // captures a weak self from a @Sendable closure.
            MainActor.assumeIsolated { self?.refreshHotkeyMenuTitles() }
        }

        if !Settings.hasCompletedOnboarding {
            // Defer slightly so the status bar item is fully laid out before
            // the onboarding window is brought to front.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                OnboardingWindowController.show()
            }
        }
    }

    private func refreshHotkeyMenuTitles() {
        singleShotMenuItem?.title = "Single Shot  \(HotkeyDisplay.format(Settings.singleShotHotkey))"
        multiShotMenuItem?.title  = "Multi Shot  \(HotkeyDisplay.format(Settings.multiShotHotkey))"
    }

    @objc private func showOnboarding() {
        OnboardingWindowController.show()
    }

    @objc private func triggerSingle() { runCapture(mode: .focus) }
    @objc private func triggerMulti()  { CaptureAndPaste.runMultiShot() }

    private func runCapture(mode: CaptureMode) {
        DispatchQueue.global(qos: .userInitiated).async {
            CaptureAndPaste.run(mode: mode)
        }
    }

    // MARK: Target App menu

    func menuWillOpen(_ menu: NSMenu) {
        if menu === targetSubmenu { rebuildTargetSubmenu() }
        if menu === pasteSubmenu  { rebuildPasteSubmenu() }
    }

    // MARK: Paste shortcut menu

    private func rebuildPasteSubmenu() {
        pasteSubmenu.removeAllItems()
        let current = Settings.pasteShortcut
        for option in Settings.PasteShortcut.allCases {
            let item = NSMenuItem(title: option.label, action: #selector(selectPaste(_:)), keyEquivalent: "")
            item.representedObject = option.rawValue
            item.state = (option == current) ? .on : .off
            item.target = self
            pasteSubmenu.addItem(item)
        }
    }

    @objc private func selectPaste(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let v = Settings.PasteShortcut(rawValue: raw) else { return }
        Settings.pasteShortcut = v
        refreshPasteMenuTitle()
    }

    private func refreshPasteMenuTitle() {
        pasteMenuItem?.title = "Paste Shortcut: \(Settings.pasteShortcut.label)"
    }

    private func rebuildTargetSubmenu() {
        targetSubmenu.removeAllItems()

        let current = Settings.targetBundleID
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (id, name)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }

        for (id, name) in running {
            let item = NSMenuItem(title: name, action: #selector(selectTarget(_:)), keyEquivalent: "")
            item.representedObject = id
            item.state = (id == current) ? .on : .off
            item.target = self
            targetSubmenu.addItem(item)
        }

        // If the saved target isn't currently running, still show it (greyed) at the top.
        if let id = current, !running.contains(where: { $0.0 == id }) {
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?
                .deletingPathExtension().lastPathComponent ?? id
            let item = NSMenuItem(title: "\(name)  (not running)", action: #selector(selectTarget(_:)), keyEquivalent: "")
            item.representedObject = id
            item.state = .on
            item.target = self
            targetSubmenu.insertItem(item, at: 0)
        }

        targetSubmenu.addItem(.separator())

        let chooseItem = NSMenuItem(title: "Choose Application…", action: #selector(chooseApplication), keyEquivalent: "")
        chooseItem.target = self
        targetSubmenu.addItem(chooseItem)

        if current != nil {
            let clearItem = NSMenuItem(title: "Clear (use last frontmost)", action: #selector(clearTarget), keyEquivalent: "")
            clearItem.target = self
            targetSubmenu.addItem(clearItem)
        }
    }

    @objc private func selectTarget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Settings.targetBundleID = id
        refreshTargetMenuTitle()
    }

    @objc private func clearTarget() {
        Settings.targetBundleID = nil
        refreshTargetMenuTitle()
    }

    @objc private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Select"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
            Settings.targetBundleID = id
            refreshTargetMenuTitle()
        }
    }

    private func refreshTargetMenuTitle() {
        let label: String
        if let id = Settings.targetBundleID {
            let name = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == id })?.localizedName
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?
                    .deletingPathExtension().lastPathComponent
                ?? id
            label = "Target: \(name)"
        } else {
            label = "Target: (last frontmost)"
        }
        targetMenuItem?.title = label
    }
}
