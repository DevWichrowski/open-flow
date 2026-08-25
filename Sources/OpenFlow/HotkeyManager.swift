import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Which of the two push-to-talk bindings fired.
enum HotkeyRole: String {
    case dictate
    case translate
}

/// A single push-to-talk key: either a modifier (right ⌘, Fn, …) identified by
/// its device-dependent flag bit, or a regular key identified by key code only.
/// Push-to-talk is a *held* key, so combinations like ⌘⇧X are deliberately not
/// supported: holding a chord while talking is miserable.
struct HotkeySpec: Codable, Equatable, Hashable {
    let keyCode: Int64
    /// Device-dependent modifier bit (IOLLEvent.h `NX_DEVICE*KEYMASK`).
    /// Non-nil means this is a modifier key tracked via flagsChanged.
    let deviceMask: UInt64?

    var isModifier: Bool { deviceMask != nil }

    static let rightCommand = HotkeySpec(keyCode: 54, deviceMask: 0x0000_0010)
    static let rightControl = HotkeySpec(keyCode: 62, deviceMask: 0x0000_2000)

    /// keyCode to mask and localization key for every modifier we accept. Caps Lock is
    /// excluded on purpose: it toggles instead of holding.
    private static let modifiers: [Int64: (mask: UInt64, labelKey: String)] = [
        54: (0x0000_0010, "hotkey.right_command"),
        55: (0x0000_0008, "hotkey.left_command"),
        56: (0x0000_0002, "hotkey.left_shift"),
        60: (0x0000_0004, "hotkey.right_shift"),
        59: (0x0000_0001, "hotkey.left_control"),
        62: (0x0000_2000, "hotkey.right_control"),
        58: (0x0000_0020, "hotkey.left_option"),
        61: (0x0000_0040, "hotkey.right_option"),
        63: (CGEventFlags.maskSecondaryFn.rawValue, "hotkey.fn"),
    ]

    private static let specialKeys: [Int64: String] = [
        36: "Return", 51: "⌫ Delete", 76: "Enter",
        114: "Help", 115: "Home", 116: "Page Up", 117: "⌦ Delete",
        119: "End", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    static func modifier(forKeyCode keyCode: Int64) -> HotkeySpec? {
        guard let entry = modifiers[keyCode] else { return nil }
        return HotkeySpec(keyCode: keyCode, deviceMask: entry.mask)
    }

    func label(language: AppLanguage) -> String {
        if isModifier, let entry = Self.modifiers[keyCode] {
            return L10n.text(entry.labelKey, language: language)
        }
        if keyCode == 49 { return L10n.text("hotkey.space", language: language) }
        if let name = Self.specialKeys[keyCode] { return name }
        return Self.printableName(for: keyCode)
            ?? L10n.text("hotkey.key", language: language, keyCode)
    }

    func note(language: AppLanguage) -> String? {
        switch keyCode {
        case 61:
            return L10n.text("hotkey.note.right_option", language: language)
        case 63:
            return L10n.text("hotkey.note.fn", language: language)
        default:
            return nil
        }
    }

    /// Resolves a printable key's label from the current keyboard layout.
    private static func printableName(for keyCode: Int64) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: chars, count: length).uppercased()
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    }
}

/// Watches two global push-to-talk keys (dictation and translation) and TAB
/// pressed while one of them is held. Requires the Accessibility permission.
///
/// The tap is an *active* one (`.defaultTap`), because two things must be
/// swallowed before they reach the frontmost app: TAB during recording (which
/// would move focus, or trigger ⌘Tab), and any regular key used as a hotkey
/// (which would type characters while held).
final class HotkeyManager {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeRole: HotkeyRole?
    private var swallowTabKeyUp = false
    private var captureCompletion: ((HotkeySpec?) -> Void)?

    var dictationKey: HotkeySpec = .rightCommand
    var translationKey: HotkeySpec = .rightControl
    var onPress: ((HotkeyRole) -> Void)?
    var onRelease: ((HotkeyRole) -> Void)?
    /// TAB pressed while a hotkey is held (recording in progress).
    var onTab: (() -> Void)?

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt pointing the user at Privacy & Security.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        stop()
        guard Self.hasAccessibilityPermission else { return false }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: context
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil

        if let completion = captureCompletion {
            captureCompletion = nil
            DispatchQueue.main.async { completion(nil) }
        }

        // Never strand a caller mid-recording.
        if let role = activeRole {
            activeRole = nil
            DispatchQueue.main.async { [onRelease] in onRelease?(role) }
        }
    }

    // MARK: - Capture

    /// The next key pressed (a modifier or a regular key) becomes the captured
    /// spec; Escape cancels with nil. Used by the "click, then press a key"
    /// recorder in Settings.
    func beginCapture(completion: @escaping (HotkeySpec?) -> Void) {
        guard isRunning else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        // A capture started while one is pending cancels the old one.
        if let previous = captureCompletion {
            DispatchQueue.main.async { previous(nil) }
        }
        captureCompletion = completion
    }

    func cancelCapture() {
        if let completion = captureCompletion {
            captureCompletion = nil
            DispatchQueue.main.async { completion(nil) }
        }
    }

    private func finishCapture(_ spec: HotkeySpec?) {
        guard let completion = captureCompletion else { return }
        captureCompletion = nil
        DispatchQueue.main.async { completion(spec) }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that blocks for too long; bring it straight back.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if captureCompletion != nil {
            return handleCapture(type: type, event: event, keyCode: keyCode)
        }

        switch type {
        case .flagsChanged:
            handleFlagsChanged(event: event, keyCode: keyCode)
            // Blocking flagsChanged would desynchronise modifier state
            // system-wide, and a held modifier types nothing anyway.
            return Unmanaged.passUnretained(event)

        case .keyDown:
            // TAB while a hotkey is held: cycle language/style, never let the
            // frontmost app (or the ⌘Tab switcher) see it.
            if keyCode == 48, activeRole != nil {
                swallowTabKeyUp = true
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    DispatchQueue.main.async { [onTab] in onTab?() }
                }
                return nil
            }
            if let role = regularBindingRole(for: keyCode) {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0, activeRole == nil {
                    activeRole = role
                    DispatchQueue.main.async { [onPress] in onPress?(role) }
                }
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .keyUp:
            if keyCode == 48, swallowTabKeyUp {
                swallowTabKeyUp = false
                return nil
            }
            if let role = regularBindingRole(for: keyCode) {
                if activeRole == role {
                    activeRole = nil
                    DispatchQueue.main.async { [onRelease] in onRelease?(role) }
                }
                return nil
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleCapture(type: CGEventType, event: CGEvent, keyCode: Int64) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            if keyCode == 53 { // Escape cancels
                finishCapture(nil)
                return nil
            }
            if keyCode == 48 { // TAB is reserved for language/style cycling
                return nil
            }
            finishCapture(HotkeySpec(keyCode: keyCode, deviceMask: nil))
            return nil
        case .flagsChanged:
            // Capture on press (bit set), ignore the matching release.
            if let spec = HotkeySpec.modifier(forKeyCode: keyCode),
               let mask = spec.deviceMask,
               event.flags.rawValue & mask != 0 {
                finishCapture(spec)
            }
            return Unmanaged.passUnretained(event)
        default:
            // keyUp and anything else passes through: swallowing a keyUp for a
            // key pressed before capture began would leave the frontmost app
            // with a stuck key.
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(event: CGEvent, keyCode: Int64) {
        for (role, spec) in [(HotkeyRole.dictate, dictationKey), (.translate, translationKey)] {
            guard let mask = spec.deviceMask, spec.keyCode == keyCode else { continue }
            let pressed = event.flags.rawValue & mask != 0

            if pressed, activeRole == nil {
                activeRole = role
                DispatchQueue.main.async { [onPress] in onPress?(role) }
            } else if !pressed, activeRole == role {
                activeRole = nil
                DispatchQueue.main.async { [onRelease] in onRelease?(role) }
            }
        }
    }

    private func regularBindingRole(for keyCode: Int64) -> HotkeyRole? {
        if !dictationKey.isModifier, dictationKey.keyCode == keyCode { return .dictate }
        if !translationKey.isModifier, translationKey.keyCode == keyCode { return .translate }
        return nil
    }

    deinit {
        stop()
    }
}
