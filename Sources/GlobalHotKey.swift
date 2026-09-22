import Carbon.HIToolbox

/// A system-wide keyboard shortcut that works while another app is in front.
///
/// Uses Carbon's RegisterEventHotKey, which is still the supported way to do
/// this: unlike a global NSEvent monitor it needs no Accessibility permission,
/// and it swallows the key press so the frontmost app never sees it.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// Fails if the combination is already taken by another app.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                    eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
                return noErr
            },
            1, &pressed,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef)
        guard installed == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x5444_4F4C), id: 1)   // 'TDOL'
        let registered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                             GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    deinit {
        if let hotKeyRef = hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef = handlerRef { RemoveEventHandler(handlerRef) }
    }
}
