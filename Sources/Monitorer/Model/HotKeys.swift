import Carbon.HIToolbox
import Foundation

/// Global shortcuts through Carbon's `RegisterEventHotKey`: no Accessibility permission
/// and no dependency. Registration fails, rather than stealing the keys, for combinations
/// the system or another app already owns.
@MainActor
final class HotKeys {
    struct Shortcut: Hashable {
        let keyCode: UInt32
        let modifiers: UInt32
        /// What Settings shows; the key code itself can't be turned back into a glyph cheaply.
        let display: String
    }

    private var registered: [UInt32: (ref: EventHotKeyRef, action: @MainActor () -> Void)] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1

    /// Returns false when the combination is taken.
    @discardableResult
    func register(_ shortcut: Shortcut, action: @escaping @MainActor () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        registered[id] = (ref, action)
        return true
    }

    func unregisterAll() {
        for entry in registered.values { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()
    }

    private func fire(_ id: UInt32) {
        registered[id]?.action()
    }

    fileprivate static let signature: OSType = 0x4D4E_5452  // "MNTR"

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Unretained: the handler is never removed, which is safe only because the one HotKeys
        // instance lives in the App's @State for the whole process. Don't create short-lived ones.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            // Leave other apps' and the system's hot keys to their own handlers.
            guard status == noErr, hotKeyID.signature == HotKeys.signature else { return OSStatus(eventNotHandledErr) }
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            let id = hotKeyID.id
            // Carbon delivers on the main thread; hop explicitly so the isolation is checked.
            DispatchQueue.main.async { MainActor.assumeIsolated { hotKeys.fire(id) } }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}

/// ⌃⌥⌘↑ and ⌃⌥⌘↓ step the monitor's brightness, so it can be changed without opening the panel.
@MainActor
@Observable
final class BrightnessShortcuts {
    static let up = HotKeys.Shortcut(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey | optionKey | cmdKey), display: "⌃⌥⌘↑")
    static let down = HotKeys.Shortcut(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey | optionKey | cmdKey), display: "⌃⌥⌘↓")
    static let step = 10.0

    /// Shortcuts another app or the system already owns; Settings marks them.
    private(set) var unavailable: [HotKeys.Shortcut] = []

    @ObservationIgnored private let hotKeys = HotKeys()
    @ObservationIgnored private let model: MonitorModel

    init(model: MonitorModel) {
        self.model = model
    }

    func apply(enabled: Bool) {
        hotKeys.unregisterAll()
        unavailable = []
        guard enabled, !RunMode.isReadOnly else { return }
        for (shortcut, delta) in [(Self.up, Self.step), (Self.down, -Self.step)] {
            let ok = hotKeys.register(shortcut) { [model] in
                Task { await model.nudge(.luminance, by: delta) }
            }
            if !ok { unavailable.append(shortcut) }
        }
    }
}
