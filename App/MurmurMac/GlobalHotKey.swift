import Carbon.HIToolbox
import Foundation
import MurmurCore

/// One system-wide hot key (works while Murmur is in the background).
final class GlobalHotKey: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (@Sendable () -> Void)?

    func register(_ shortcut: RecordShortcut, action: @escaping @Sendable () -> Void) {
        unregister()
        guard shortcut.isValid else { return }
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            me.action?()
            return noErr
        }, 1, &spec, pointer, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4D55_5252), id: 1)
        RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.carbonModifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        action = nil
    }

    deinit { unregister() }
}
