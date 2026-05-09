import AppKit
import Carbon.HIToolbox
import ApplicationServices

enum CaptureMode {
    case focus       // single shot: bring target to front, then paste
    case background  // (legacy) single background paste into target
}

enum CaptureAndPaste {

    // MARK: - Single shot

    static func run(mode: CaptureMode) {
        Log.write("run(mode: \(mode))")
        let pb = NSPasteboard.general
        let beforeChange = pb.changeCount

        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-i", "-c", "-x"]
        do {
            try task.run()
        } catch {
            Log.write("run: screencapture launch failed: \(error)")
            return
        }
        task.waitUntilExit()

        guard pb.changeCount != beforeChange else {
            Log.write("run: pasteboard unchanged — user cancelled snip")
            return
        }
        guard pb.canReadObject(forClasses: [NSImage.self], options: nil) else {
            Log.write("run: pasteboard changed but no NSImage available")
            return
        }
        Log.write("run: image captured, dispatching paste (mode=\(mode))")

        DispatchQueue.main.async {
            switch mode {
            case .focus:      activateTargetThenPaste()
            case .background: backgroundPasteToTarget()
            }
        }
    }

    // MARK: - Multi shot (loop captures, then paste all)

    @MainActor
    static func runMultiShot() {
        if let s = activeSession {
            Log.write("runMultiShot: re-press during active session — ending")
            s.requestEnd()
            return
        }

        guard Settings.targetBundleID != nil else {
            Log.write("runMultiShot: no target app set — beeping")
            NSSound.beep()
            return
        }

        let session = MultiShotSession()
        activeSession = session
        session.hud.show(count: 0)
        Log.write("runMultiShot: session started")

        DispatchQueue.global(qos: .userInitiated).async {
            captureLoop(session: session)
            let collected = session.images
            Log.write("runMultiShot: loop ended, collected=\(collected.count)")

            DispatchQueue.main.async {
                session.hud.close()
                activeSession = nil
                if collected.isEmpty { return }
                pasteAll(images: collected)
            }
        }
    }

    @MainActor private static var activeSession: MultiShotSession?

    private static func captureLoop(session: MultiShotSession) {
        let pb = NSPasteboard.general

        while !session.isEnded {
            DispatchQueue.main.sync { _ = pb.clearContents() }
            let beforeChange = pb.changeCount

            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            task.arguments = ["-i", "-c", "-x"]
            do {
                try task.run()
            } catch {
                Log.write("captureLoop: screencapture launch failed: \(error)")
                return
            }
            session.setRunningTask(task)
            task.waitUntilExit()
            session.setRunningTask(nil)

            if session.isEnded { break }

            // Esc inside screencapture exits without changing the pasteboard.
            if pb.changeCount == beforeChange { break }
            guard let png = readClipboardImageAsPng() else {
                Log.write("captureLoop: pasteboard changed but couldn't read image")
                break
            }

            session.append(png)
            let count = session.images.count
            Log.write("captureLoop: collected #\(count) (\(png.count) bytes)")
            DispatchQueue.main.async { session.hud.show(count: count) }
        }
    }

    // MARK: - Single shot focus path

    private static func activateTargetThenPaste() {
        let targetID = Settings.targetBundleID
        let flags = resolveModifier(for: targetID)

        guard let targetID = targetID else {
            Log.write("activate: no target — pasting into current frontmost")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                postPaste(flags: flags)
            }
            return
        }

        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == targetID }) {
            Log.write("activate: target \(targetID) running, pid=\(running.processIdentifier)")
            running.activate(options: [.activateIgnoringOtherApps])
            // Activation needs ~250ms before chat apps surface their input.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                focusInputAreaIfNeeded(pid: running.processIdentifier, bundleID: targetID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    postPaste(flags: flags)
                }
            }
            return
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetID) else {
            Log.write("activate: target app \(targetID) not found on disk")
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { app, error in
            if let error = error {
                Log.write("activate: launch \(targetID) failed: \(error)")
                return
            }
            let pid = app?.processIdentifier ?? 0
            Log.write("activate: launched \(targetID), pid=\(pid)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                focusInputAreaIfNeeded(pid: pid, bundleID: targetID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    postPaste(flags: flags)
                }
            }
        }
    }

    private static func backgroundPasteToTarget() {
        guard let targetID = Settings.targetBundleID else {
            Log.write("backgroundPaste: no target")
            return
        }
        guard let target = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == targetID }) else {
            Log.write("backgroundPaste: target \(targetID) not running")
            return
        }
        postPaste(flags: resolveModifier(for: targetID), toPid: target.processIdentifier)
    }

    // MARK: - Paste-all sequence (multi-shot)

    private static func pasteAll(images: [Data]) {
        let targetID = Settings.targetBundleID
        let flags = resolveModifier(for: targetID)
        let prevApp = NSWorkspace.shared.frontmostApplication
        Log.write("pasteAll: \(images.count) images, target=\(targetID ?? "<none>"), prev=\(prevApp?.bundleIdentifier ?? "<none>")")

        guard let targetID = targetID else {
            DispatchQueue.global(qos: .userInitiated).async {
                pasteSequence(images: images, flags: flags, pid: nil, bundleID: nil)
            }
            return
        }

        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == targetID }) {
            running.activate(options: [.activateIgnoringOtherApps])
            let pid = running.processIdentifier
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.30) {
                pasteSequence(images: images, flags: flags, pid: pid, bundleID: targetID)
                if let prev = prevApp, prev.bundleIdentifier != targetID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        prev.activate(options: [.activateIgnoringOtherApps])
                    }
                }
            }
            return
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetID) else {
            Log.write("pasteAll: target app \(targetID) not found")
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { app, error in
            if let error = error {
                Log.write("pasteAll: launch failed: \(error)")
                return
            }
            let pid = app?.processIdentifier ?? 0
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.7) {
                pasteSequence(images: images, flags: flags, pid: pid, bundleID: targetID)
                if let prev = prevApp, prev.bundleIdentifier != targetID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        prev.activate(options: [.activateIgnoringOtherApps])
                    }
                }
            }
        }
    }

    /// Per-image: republish clipboard → focus input → ⌘V → wait. The pause
    /// gives chat apps (Claude desktop, Slack, Discord) time to finish ingesting
    /// one attachment before we slam the next one in.
    private static func pasteSequence(images: [Data], flags: CGEventFlags, pid: pid_t?, bundleID: String?) {
        for (i, png) in images.enumerated() {
            DispatchQueue.main.sync { setClipboardImage(png) }
            Thread.sleep(forTimeInterval: 0.15)

            if let pid = pid, pid > 0 {
                DispatchQueue.main.sync {
                    focusInputAreaIfNeeded(pid: pid, bundleID: bundleID)
                }
                Thread.sleep(forTimeInterval: 0.10)
            }

            DispatchQueue.main.sync { postPaste(flags: flags) }
            Log.write("pasteSequence: pasted #\(i + 1)/\(images.count)")
            if i < images.count - 1 {
                Thread.sleep(forTimeInterval: 0.9)
            }
        }
    }

    // MARK: - Focus the chat-app input field via a synthesized click

    /// Chat apps (Claude desktop, Slack, Discord) often surface the window on
    /// activation but leave focus on a non-text element, so ⌘V silently does
    /// nothing. A click at the bottom-center of the focused window lands on
    /// the textarea and gives the keystroke somewhere to go.
    /// Skipped for known terminal emulators where focus is naturally on the
    /// input row.
    private static func focusInputAreaIfNeeded(pid: pid_t, bundleID: String?) {
        if let id = bundleID, Settings.terminalBundleIDs.contains(id) {
            Log.write("focusInputArea: terminal target — skip click")
            return
        }
        guard pid > 0, let frame = focusedWindowFrame(forPid: pid) else {
            Log.write("focusInputArea: no AX frame for pid=\(pid)")
            return
        }
        let clickX = frame.midX
        let clickY = frame.maxY - frame.height * 0.10  // 90% down from window top
        Log.write("focusInputArea: clicking (\(Int(clickX)), \(Int(clickY))) within \(frame)")
        synthesizeClick(at: CGPoint(x: clickX, y: clickY))
    }

    private static func focusedWindowFrame(forPid pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)

        var winRef: CFTypeRef?
        var status = AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &winRef)
        if status != .success || winRef == nil {
            // Fall back to the first window if no focused one is reported.
            var windowsRef: CFTypeRef?
            status = AXUIElementCopyAttributeValue(
                app, kAXWindowsAttribute as CFString, &windowsRef)
            guard status == .success,
                  let arr = windowsRef as? [AXUIElement],
                  let first = arr.first else { return nil }
            winRef = first
        }
        guard let win = winRef else { return nil }
        let window = win as! AXUIElement

        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posVal)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeVal)
        guard let pv = posVal, let sv = sizeVal else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)
        guard size.width > 0 && size.height > 0 else { return nil }

        return CGRect(origin: pos, size: size)
    }

    private static func synthesizeClick(at point: CGPoint) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        // Save and restore cursor so the user's mouse doesn't visibly jump.
        let originalCursor = CGEvent(source: src)?.location ?? point

        CGWarpMouseCursorPosition(point)
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)
        let up   = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                           mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        CGWarpMouseCursorPosition(originalCursor)
    }

    // MARK: - Clipboard helpers

    private static func readClipboardImageAsPng() -> Data? {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) { return data }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
    }

    private static func setClipboardImage(_ png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        if let img = NSImage(data: png), let tiff = img.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    // MARK: - Modifier resolution

    private static func resolveModifier(for bundleID: String?) -> CGEventFlags {
        switch Settings.pasteShortcut {
        case .commandV: return .maskCommand
        case .controlV: return .maskControl
        case .auto:
            guard let id = bundleID else { return .maskCommand }
            return Settings.terminalBundleIDs.contains(id) ? .maskControl : .maskCommand
        }
    }

    // MARK: - Keystroke synthesis

    private static func postPaste(flags: CGEventFlags) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            Log.write("postPaste: failed to create event source")
            return
        }
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        Log.write("postPaste: dispatched, flags=\(flags.rawValue), trusted=\(AXIsProcessTrusted())")
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
        Log.write("postPaste(pid=\(pid)): dispatched, flags=\(flags.rawValue)")
    }
}

// MARK: - Multi-shot session

final class MultiShotSession: @unchecked Sendable {
    private let lock = NSLock()
    private var _ended = false
    private var _runningTask: Process?
    private(set) var images: [Data] = []
    let hud: MultiShotHUD

    @MainActor
    init() {
        self.hud = MultiShotHUD()
    }

    var isEnded: Bool {
        lock.lock(); defer { lock.unlock() }
        return _ended
    }

    func requestEnd() {
        lock.lock()
        _ended = true
        let task = _runningTask
        lock.unlock()
        if let t = task, t.isRunning { t.terminate() }
    }

    func setRunningTask(_ t: Process?) {
        lock.lock(); _runningTask = t; lock.unlock()
    }

    func append(_ png: Data) {
        lock.lock(); images.append(png); lock.unlock()
    }
}

// MARK: - Multi-shot HUD overlay

@MainActor
final class MultiShotHUD {
    private var panel: NSPanel?
    private var titleLabel: NSTextField?
    private var hintLabel: NSTextField?
    private var dot: NSView?

    func show(count: Int) {
        if panel == nil { build() }
        titleLabel?.stringValue = count == 0
            ? "Multi-shot — 0 captured"
            : "Multi-shot — \(count) captured"
        hintLabel?.stringValue = "Drag to snip. Press \(HotkeyDisplay.format(Settings.multiShotHotkey)) again to finish & paste."
        panel?.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        titleLabel = nil
        hintLabel = nil
        dot = nil
    }

    private func build() {
        let width: CGFloat = 380
        let height: CGFloat = 56

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true

        let dotSize: CGFloat = 10
        let dotView = NSView(frame: NSRect(
            x: 16, y: (height - dotSize) / 2, width: dotSize, height: dotSize))
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.layer?.cornerRadius = dotSize / 2

        let title = NSTextField(labelWithString: "Multi-shot — 0 captured")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 36, y: height - 30, width: width - 48, height: 18)

        let hint = NSTextField(labelWithString: "Drag to snip.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 36, y: 8, width: width - 48, height: 16)

        bg.addSubview(dotView)
        bg.addSubview(title)
        bg.addSubview(hint)
        p.contentView = bg

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(
                x: f.midX - width / 2,
                y: f.maxY - height - 24
            ))
        }

        panel = p
        titleLabel = title
        hintLabel = hint
        dot = dotView
    }
}

// MARK: - File logging

/// Append-only log at ~/Library/Logs/Snapline/snapline.log. Mirrors the
/// Windows version so users can share a diagnostic file when paste/capture
/// stops working.
enum Log {
    private static let lock = NSLock()
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Snapline", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snapline.log")
    }()

    static func write(_ msg: String) {
        let stamp = DateFormatter.timestamp.string(from: Date())
        let line = "\(stamp) \(msg)\n"
        lock.lock(); defer { lock.unlock() }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            if let d = line.data(using: .utf8) { h.write(d) }
            try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }
}

private extension DateFormatter {
    static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
