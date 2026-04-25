import AppKit
import Carbon.HIToolbox
import Foundation

/// Registers and manages global keyboard shortcuts using the Carbon Event Manager.
/// Carbon's RegisterEventHotKey requires neither Accessibility nor Input Monitoring permission.
/// Supports multiple simultaneous hotkeys distinguished by a numeric id.
///
/// id=1  text pipeline trigger (⌥Space by default)
/// id=2  voice start trigger   (⌥R by default)
/// id=3  voice stop trigger    (⌥S, fixed)
@MainActor
final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    var onTrigger: (() -> Void)? // text pipeline
    var onVoiceStart: (() -> Void)? // voice start
    var onVoiceStop: (() -> Void)? // voice stop

    private(set) var currentHotKey: HotKey = .defaultYoweeTrigger
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    // MARK: - Text pipeline

    func registerYoweeTrigger(_ hotKey: HotKey = .defaultYoweeTrigger) {
        currentHotKey = hotKey
        installEventHandlerIfNeeded()
        registerHotKey(hotKey, id: 1)
    }

    func updateYoweeTrigger(_ hotKey: HotKey) {
        currentHotKey = hotKey
        unregisterHotKey(id: 1)
        registerHotKey(hotKey, id: 1)
    }

    // MARK: - Voice shortcuts

    func registerVoice(start: HotKey, stop: HotKey) {
        installEventHandlerIfNeeded()
        registerHotKey(start, id: 2)
        registerHotKey(stop, id: 3)
    }

    func updateVoiceStart(_ hotKey: HotKey) {
        unregisterHotKey(id: 2)
        registerHotKey(hotKey, id: 2)
    }

    // MARK: - Private

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let ptr = userData else { return OSStatus(eventNotHandledErr) }
                let mgr = Unmanaged<GlobalShortcutManager>.fromOpaque(ptr).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    UInt32(kEventParamDirectObject),
                    UInt32(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let triggeredID = hotKeyID.id
                DispatchQueue.main.async {
                    switch triggeredID {
                    case 1: mgr.onTrigger?()
                    case 2: mgr.onVoiceStart?()
                    case 3: mgr.onVoiceStop?()
                    default: break
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
    }

    private func registerHotKey(_ hotKey: HotKey, id: UInt32) {
        unregisterHotKey(id: id)
        let hotKeyID = EventHotKeyID(signature: 0x464C_4F57, id: id)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if let ref { hotKeyRefs[id] = ref }
    }

    private func unregisterHotKey(id: UInt32) {
        if let ref = hotKeyRefs[id] { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeValue(forKey: id)
    }
}
