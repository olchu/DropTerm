import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotKeyService {
    enum RegistrationError: LocalizedError {
        case eventHandler(OSStatus)
        case hotKey(OSStatus)

        var errorDescription: String? {
            switch self {
            case .eventHandler(let status):
                "Could not install the hot-key event handler (status \(status))."
            case .hotKey(let status):
                "Could not register the hot key (status \(status))."
            }
        }
    }

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let action: @MainActor () -> Void

    static func optionSpace(action: @escaping @MainActor () -> Void) throws -> GlobalHotKeyService {
        try GlobalHotKeyService(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey),
            action: action
        )
    }

    private init(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping @MainActor () -> Void
    ) throws {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<GlobalHotKeyService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    service.action()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            throw RegistrationError.eventHandler(handlerStatus)
        }

        let identifier = EventHotKeyID(signature: 0x4454_524D, id: 1) // DTRM
        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard hotKeyStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
            }
            throw RegistrationError.hotKey(hotKeyStatus)
        }
    }

    func invalidate() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
