import Carbon.HIToolbox
import AppKit

final class HotkeyManager {
    enum Action: UInt32 { case singleShot = 1, multiShot = 2 }

    var onTrigger: (Action) -> Void = { _ in }
    private var refs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    func register() {
        let signature: OSType = 0x434C5348 // 'CLSH'
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

        // ⌘⇧9 — single shot (focus target, then paste)
        registerKey(signature: signature, id: .singleShot,
                    keyCode: UInt32(kVK_ANSI_9),
                    modifiers: UInt32(cmdKey | shiftKey))

        // ⌘⌥⇧9 — multi shot (background paste, no focus change)
        registerKey(signature: signature, id: .multiShot,
                    keyCode: UInt32(kVK_ANSI_9),
                    modifiers: UInt32(cmdKey | shiftKey | optionKey))
    }

    private func registerKey(signature: OSType, id: Action, keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: signature, id: id.rawValue)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }

    deinit {
        for ref in refs { if let r = ref { UnregisterEventHotKey(r) } }
        if let h = handlerRef { RemoveEventHandler(h) }
    }
}
