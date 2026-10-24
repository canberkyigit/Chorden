import Carbon

/// System-wide shortcut (⌃⌥T) that opens the menu bar tuner from any app.
/// Carbon hot keys need no Accessibility permission.
enum HotKey {
    nonisolated(unsafe) private static var action: (() -> Void)?
    nonisolated(unsafe) private static var ref: EventHotKeyRef?

    static func register(_ handler: @escaping () -> Void) {
        action = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.action?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x544F_4E43), id: 1) // 'TONC'
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &ref)
    }
}
