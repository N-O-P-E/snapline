import Carbon.HIToolbox
import AppKit

final class HotkeyManager {
    enum Action: UInt32 { case singleShot = 1, multiShot = 2 }

    var onTrigger: (Action) -> Void = { _ in }
    private var refs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var observer: NSObjectProtocol?

    func register() {
        installHandlerIfNeeded()
        registerCurrentBindings()

        observer = NotificationCenter.default.addObserver(
            forName: HotkeyBinding.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.reregister()
        }
    }

    func reregister() {
        unregisterAll()
        registerCurrentBindings()
    }

    private func registerCurrentBindings() {
        let signature: OSType = 0x434C5348 // 'CLSH'
        let single = Settings.singleShotHotkey
        let multi  = Settings.multiShotHotkey

        registerKey(signature: signature, id: .singleShot,
                    keyCode: single.keyCode, modifiers: single.modifiers)
        registerKey(signature: signature, id: .multiShot,
                    keyCode: multi.keyCode, modifiers: multi.modifiers)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, ud in
                guard let event = event, let ud = ud else { return noErr }
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard status == noErr else { return noErr }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(ud).takeUnretainedValue()
                if let action = Action(rawValue: hkID.id) {
                    DispatchQueue.main.async { mgr.onTrigger(action) }
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
    }

    private func registerKey(signature: OSType, id: Action, keyCode: UInt32, modifiers: UInt32) {
        guard keyCode != 0 else { return }
        let hotKeyID = EventHotKeyID(signature: signature, id: id.rawValue)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }

    private func unregisterAll() {
        for ref in refs { if let r = ref { UnregisterEventHotKey(r) } }
        refs.removeAll()
    }

    deinit {
        unregisterAll()
        if let h = handlerRef { RemoveEventHandler(h) }
        if let obs = observer { NotificationCenter.default.removeObserver(obs) }
    }
}
