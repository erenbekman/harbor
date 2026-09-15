import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut through Carbon: `NSEvent`'s global monitor would need
/// the Accessibility permission for the same thing.
enum HotKey {
    static var onPress: (() -> Void)?

    private static var ref: EventHotKeyRef?
    private static var installed = false

    static func register(keyCode: UInt32 = UInt32(kVK_ANSI_H),
                         modifiers: UInt32 = UInt32(controlKey | cmdKey)) {
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.onPress?() }
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x48_52_42_52), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}
