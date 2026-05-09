import SwiftUI
import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static var shared: OnboardingWindowController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Snapline"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self

        let view = OnboardingView(onComplete: { [weak self] in
            Settings.hasCompletedOnboarding = true
            self?.close()
        })
        window.contentView = NSHostingView(rootView: view)
    }

    static func show() {
        if shared == nil { shared = OnboardingWindowController() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        shared?.showWindow(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Permission state model

@MainActor
private final class PermissionState: ObservableObject {
    @Published var accessibilityGranted: Bool = AXIsProcessTrusted()
    @Published var screenRecordingGranted: Bool = CGPreflightScreenCaptureAccess()
    @Published var targetBundleID: String? = Settings.targetBundleID
    @Published var singleShotHotkey: HotkeyBinding = Settings.singleShotHotkey
    @Published var multiShotHotkey:  HotkeyBinding = Settings.multiShotHotkey

    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        targetBundleID = Settings.targetBundleID
        singleShotHotkey = Settings.singleShotHotkey
        multiShotHotkey = Settings.multiShotHotkey
    }

    var allReady: Bool {
        accessibilityGranted && screenRecordingGranted && targetBundleID != nil
    }
}

// MARK: - Root

private struct OnboardingView: View {
    let onComplete: () -> Void
    @StateObject private var state = PermissionState()

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(state: state)
                .frame(width: 300)

            MainPane(state: state, onFinish: onComplete)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 880, height: 600)
        .background(Color(red: 0.04, green: 0.04, blue: 0.06))
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var state: PermissionState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppIconView()
                .frame(width: 84, height: 84)
                .padding(.top, 24)
                .padding(.bottom, 24)

            Text("Welcome to Snapline")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            Text("Let's get everything set up so you can start capturing and sending anywhere.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .lineSpacing(2)
                .padding(.top, 10)
                .padding(.trailing, 24)

            VStack(alignment: .leading, spacing: 18) {
                StepListItem(number: 1, title: "Accessibility",
                             subtitle: "Required for global capture and hotkeys.",
                             done: state.accessibilityGranted)
                StepListItem(number: 2, title: "Screen Recording",
                             subtitle: "Required to capture your screen.",
                             done: state.screenRecordingGranted)
                StepListItem(number: 3, title: "Pick Target App",
                             subtitle: "Choose where snapshots will be sent.",
                             done: state.targetBundleID != nil)
                StepListItem(number: 4, title: "Hotkeys",
                             subtitle: "Customize your single- and multi-shot keys.",
                             done: true)
            }
            .padding(.top, 36)

            Spacer()

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your data stays on your Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("We never store or upload anything.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AppIconView: View {
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.18, green: 0.18, blue: 0.28), .black],
                        startPoint: .top, endPoint: .bottom))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct StepListItem: View {
    let number: Int
    let title: String
    let subtitle: String
    let done: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.accentColor : Color.white.opacity(0.08))
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Main pane

private struct MainPane: View {
    @ObservedObject var state: PermissionState
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    StepCard(
                        index: 1,
                        icon: "hand.raised.fill",
                        iconBackground: AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 0.55, green: 0.40, blue: 0.95),
                                     Color(red: 0.40, green: 0.30, blue: 0.85)],
                            startPoint: .top, endPoint: .bottom)),
                        title: "Accessibility",
                        description: "Snapline needs Accessibility access to send a paste keystroke to your target app.",
                        granted: state.accessibilityGranted,
                        action: openAccessibility
                    )

                    Connector()

                    StepCard(
                        index: 2,
                        icon: "record.circle",
                        iconBackground: AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 0.30, green: 0.55, blue: 1.00),
                                     Color(red: 0.20, green: 0.40, blue: 0.95)],
                            startPoint: .top, endPoint: .bottom)),
                        title: "Screen Recording",
                        description: "Snapline uses macOS's region selector — Screen Recording permission is required.",
                        granted: state.screenRecordingGranted,
                        action: openScreenRecording
                    )

                    Connector()

                    TargetAppCard(state: state)

                    Connector()

                    HotkeysCard(state: state)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 16)
            }

            FooterBar(canFinish: state.allReady, onFinish: onFinish)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
        }
    }

    private func openAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openScreenRecording() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct Connector: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 14)
            .padding(.leading, 38)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Step card

private struct StepCard: View {
    let index: Int
    let icon: String
    let iconBackground: AnyShapeStyle
    let title: String
    let description: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(iconBackground)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("\(index). \(title)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if granted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.green)
                    Text("Access Granted")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.green.opacity(0.95))
                }
            }

            Button(granted ? "Re-open" : "Continue", action: action)
                .buttonStyle(PrimaryButtonStyle(prominent: !granted))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - Target app card

private struct TargetAppCard: View {
    @ObservedObject var state: PermissionState
    @State private var runningApps: [(id: String, name: String, icon: NSImage?)] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.30, green: 0.78, blue: 0.42),
                                 Color(red: 0.20, green: 0.62, blue: 0.32)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "scope")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("3. Pick Target App")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Choose the app where Snapline will send your snapshots.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(runningApps, id: \.id) { app in
                    AppRow(
                        name: app.name,
                        icon: app.icon,
                        selected: state.targetBundleID == app.id,
                        action: {
                            Settings.targetBundleID = app.id
                            state.targetBundleID = app.id
                        }
                    )
                    Divider().background(Color.white.opacity(0.05))
                }

                ChooseRow(action: chooseFromDisk)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .onAppear(perform: refresh)
    }

    private func refresh() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (id, name, app.icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseFromDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
            Settings.targetBundleID = id
            state.targetBundleID = id
            refresh()
        }
    }
}

private struct AppRow: View {
    let name: String
    let icon: NSImage?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 22, height: 22)
                }
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? Color.accentColor.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ChooseRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.20, green: 0.45, blue: 0.95).opacity(0.85))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Choose Application…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Text("/Applications")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hotkeys card

private struct HotkeysCard: View {
    @ObservedObject var state: PermissionState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.95, green: 0.55, blue: 0.30),
                                 Color(red: 0.85, green: 0.35, blue: 0.20)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "command")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("4. Hotkeys")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Pick the global key combos that trigger Snapline.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()

                Button("Reset") {
                    Settings.singleShotHotkey = Settings.defaultSingleShot
                    Settings.multiShotHotkey  = Settings.defaultMultiShot
                    state.refresh()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 8) {
                HotkeyCaptureRow(
                    title: "Single Shot",
                    subtitle: "Brings target to front, then pastes.",
                    binding: state.singleShotHotkey
                ) { newValue in
                    Settings.singleShotHotkey = newValue
                    state.singleShotHotkey = newValue
                }

                HotkeyCaptureRow(
                    title: "Multi Shot",
                    subtitle: "Capture multiple, then paste them all.",
                    binding: state.multiShotHotkey
                ) { newValue in
                    Settings.multiShotHotkey = newValue
                    state.multiShotHotkey = newValue
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct HotkeyCaptureRow: View {
    let title: String
    let subtitle: String
    let binding: HotkeyBinding
    let onChange: (HotkeyBinding) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()

            Text(recording ? "Press a combo…" : HotkeyDisplay.format(binding))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(recording ? Color.accentColor : .white)
                .frame(minWidth: 110, alignment: .center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(recording ? 0.10 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(recording ? Color.accentColor : Color.clear, lineWidth: 1)
                )

            Button(recording ? "Cancel" : "Record") {
                if recording { stopRecording() } else { startRecording() }
            }
            .buttonStyle(PrimaryButtonStyle(prominent: !recording))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Esc with no modifiers = cancel.
            if event.keyCode == kVK_Escape && event.modifierFlags
                .intersection(.deviceIndependentFlagsMask).isEmpty {
                stopRecording()
                return nil
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock)
            // Require at least one modifier so the user can still type elsewhere.
            guard !mods.isEmpty else { return event }

            let carbon = CarbonModifiers.mask(from: mods)
            let new = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: carbon)
            onChange(new)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

// MARK: - Footer

private struct FooterBar: View {
    let canFinish: Bool
    let onFinish: () -> Void

    var body: some View {
        HStack {
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(SecondaryButtonStyle())
            Spacer()
            Button(action: onFinish) {
                HStack(spacing: 8) {
                    Text("Finish Setup")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle(prominent: true, large: true))
            .disabled(!canFinish)
        }
    }
}

// MARK: - Button styles

private struct PrimaryButtonStyle: ButtonStyle {
    var prominent: Bool = true
    var large: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 14 : 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 22 : 16)
            .padding(.vertical, large ? 10 : 7)
            .background(
                RoundedRectangle(cornerRadius: large ? 10 : 8, style: .continuous)
                    .fill(prominent
                          ? AnyShapeStyle(LinearGradient(
                              colors: [Color(red: 0.42, green: 0.40, blue: 0.95),
                                       Color(red: 0.30, green: 0.30, blue: 0.85)],
                              startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.08)))
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.06))
            )
    }
}
