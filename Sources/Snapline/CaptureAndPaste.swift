import AppKit
import Carbon.HIToolbox

enum CaptureMode {
    case focus       // single shot: bring target to front, then paste
    case background  // multi shot: paste into target without changing focus
}

enum CaptureAndPaste {
    static func run(mode: CaptureMode) {
        let pb = NSPasteboard.general
        let beforeChange = pb.changeCount

        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-i", "-c", "-x"]
        do {
            try task.run()
        } catch {
            NSLog("Snapline: failed to run screencapture: \(error)")
            return
        }
        task.waitUntilExit()

        guard pb.changeCount != beforeChange else { return }
        guard pb.canReadObject(forClasses: [NSImage.self], options: nil) else { return }

        DispatchQueue.main.async {
            switch mode {
            case .focus:      activateTargetThenPaste()
            case .background: backgroundPasteToTarget()
            }
        }
    }

    // MARK: Single shot (focus + paste)

    private static func activateTargetThenPaste() {
        let targetID = Settings.targetBundleID
        let flags = resolveModifier(for: targetID)

        guard let targetID = targetID else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { postPaste(flags: flags) }
            return
        }

        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == targetID }) {
            running.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { postPaste(flags: flags) }
            return
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetID) else {
            NSLog("Snapline: target app \(targetID) not found")
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
            if let error = error {
                NSLog("Snapline: failed to launch \(targetID): \(error)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { postPaste(flags: flags) }
        }
    }

    // MARK: Multi shot (background paste)

    private static func backgroundPasteToTarget() {
        guard let targetID = Settings.targetBundleID else {
            NSLog("Snapline: multi-shot requires a target app — set one in the menu")
            return
        }
        guard let target = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == targetID }) else {
            NSLog("Snapline: target \(targetID) not running — multi-shot needs it open")
            return
        }
        postPaste(flags: resolveModifier(for: targetID), toPid: target.processIdentifier)
    }

    // MARK: Modifier resolution

    private static func resolveModifier(for bundleID: String?) -> CGEventFlags {
        switch Settings.pasteShortcut {
        case .commandV: return .maskCommand
        case .controlV: return .maskControl
        case .auto:
            guard let id = bundleID else { return .maskCommand }
            return Settings.terminalBundleIDs.contains(id) ? .maskControl : .maskCommand
        }
    }

    // MARK: Keystroke synthesis

    private static func postPaste(flags: CGEventFlags) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func postPaste(flags: CGEventFlags, toPid pid: pid_t) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = flags
        down?.postToPid(pid)
        up?.postToPid(pid)
    }
}
