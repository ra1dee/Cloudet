import AppKit
import Carbon.HIToolbox

struct KeyCombo: Equatable, Codable {
    var keyCode: UInt16
    var modifiers: UInt

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = ShortcutRules.chord(from: modifiers).rawValue
    }
}

enum ShortcutIssue: Equatable {
    case needsModifier
    case reservedBySystem
    case alreadyInUse
}

enum ShortcutRules {
    static func chord(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .shift, .option, .control])
    }

    static func hasChordModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        !chord(from: flags).isDisjoint(with: [.command, .option, .control])
    }

    /// Сочетания, которые macOS забирает себе и не отдаёт приложениям.
    static let alwaysReserved: [KeyCombo] = [
        KeyCombo(keyCode: 48, modifiers: .command),
        KeyCombo(keyCode: 48, modifiers: [.command, .shift]),
        KeyCombo(keyCode: 53, modifiers: [.command, .option]),
    ]

    static func isReserved(_ combo: KeyCombo, system: [KeyCombo]) -> Bool {
        let wanted = KeyCombo(keyCode: combo.keyCode, modifiers: combo.flags)
        return (alwaysReserved + system).contains(wanted)
    }
}

enum ShortcutStore {
    private static let key = "showHideShortcut"

    static func load() -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    static func save(_ combo: KeyCombo?) {
        guard let combo, let data = try? JSONEncoder().encode(combo) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum SystemHotKeys {
    static func enabled() -> [KeyCombo] {
        var storage: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&storage) == noErr, let storage else { return [] }
        let items = storage.takeRetainedValue() as? [NSDictionary] ?? []
        return items.compactMap(combo(from:))
    }

    private static func combo(from item: NSDictionary) -> KeyCombo? {
        guard (item[kHISymbolicHotKeyEnabled] as? NSNumber)?.boolValue == true else { return nil }
        guard
            let code = item[kHISymbolicHotKeyCode] as? NSNumber,
            let carbon = item[kHISymbolicHotKeyModifiers] as? NSNumber
        else { return nil }
        return KeyCombo(keyCode: UInt16(code.uint16Value), modifiers: cocoa(from: carbon.uint32Value))
    }

    private static func cocoa(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }
}

enum KeyComboLabel {
    static func string(for combo: KeyCombo) -> String {
        parts(for: combo).joined()
    }

    static func parts(for combo: KeyCombo) -> [String] {
        var parts: [String] = []
        let flags = combo.flags
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        let key = name(for: combo.keyCode)
        if !key.isEmpty { parts.append(key) }
        return parts
    }

    private static func name(for keyCode: UInt16) -> String {
        if let special = specialNames[keyCode] { return special }
        if let letter = translated(keyCode) { return letter }
        return qwerty[keyCode] ?? ""
    }

    private static let specialNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: L10n.tr("Space"), 51: "⌫", 53: "⎋", 76: "⌤",
        117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static let qwerty: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
        45: "N", 46: "M",
    ]

    private static func translated(_ keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKey: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                base,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKey,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length).uppercased()
        guard text.count == 1, text != " " else { return nil }
        return text
    }
}

private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var value: UInt32 = 0
    if flags.contains(.command) { value |= UInt32(cmdKey) }
    if flags.contains(.shift) { value |= UInt32(shiftKey) }
    if flags.contains(.option) { value |= UInt32(optionKey) }
    if flags.contains(.control) { value |= UInt32(controlKey) }
    return value
}

private func hotKeyEventHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
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
    guard status == noErr else { return status }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    guard hotKeyID.signature == center.signature, hotKeyID.id == 1 else { return noErr }
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            center.onPress?()
        }
    }
    return noErr
}

@MainActor
final class HotKeyCenter {
    var onPress: (() -> Void)?
    let signature: OSType = {
        var value: OSType = 0
        for byte in "Cldt".utf8 {
            value = (value << 8) | OSType(byte)
        }
        return value
    }()

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var combo: KeyCombo?

    func restoreSavedShortcut() {
        combo = ShortcutStore.load()
        _ = apply(combo, persist: false)
    }

    @discardableResult
    func apply(_ combo: KeyCombo?, persist: Bool) -> ShortcutIssue? {
        unregister()
        self.combo = combo
        if persist { ShortcutStore.save(combo) }
        guard let combo else { return nil }
        guard ShortcutRules.hasChordModifier(combo.flags) else { return .needsModifier }
        if ShortcutRules.isReserved(combo, system: SystemHotKeys.enabled()) {
            return .reservedBySystem
        }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            carbonModifiers(combo.flags),
            EventHotKeyID(signature: signature, id: 1),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return .alreadyInUse }
        hotKey = ref
        return nil
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }
}
