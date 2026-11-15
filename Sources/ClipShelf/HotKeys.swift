import Carbon.HIToolbox

/// System-wide hotkeys through Carbon's RegisterEventHotKey, the same API
/// ClipMenu used. It needs no Accessibility permission and still works on
/// current macOS, including Apple Silicon.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private static let signature: OSType = 0x434C5053 // "CLPS"
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    private init() {}

    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        unregister(id: id)
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("ClipShelf: could not register hotkey %u (status %d)", id, status)
            return false
        }
        refs[id] = ref
        handlers[id] = handler
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let handler = HotKeyCenter.shared.handlers[hotKeyID.id]
            DispatchQueue.main.async { handler?() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = status == noErr
    }
}
