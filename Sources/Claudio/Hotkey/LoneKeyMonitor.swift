import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

/// Plugs `LoneKeyGesture` into the real keyboard and mouse, and hands what it
/// decides to the dictation. A thin shell: which press counts, and when, is
/// the gesture's call.
///
/// Listens only while a dictation shortcut is set to a lone key, and only to
/// what the gesture needs: modifiers changing, and that some key or mouse
/// button went down — never which key, never a character. The global
/// monitors see the other apps; the local ones see Claudio's own windows,
/// Settings included, which global monitors miss. No permission of its own.
@MainActor
final class LoneKeyMonitor {
    private weak var coordinator: DictationCoordinator?
    private lazy var gesture = LoneKeyGesture(keys: [], guards: .system,
                                              schedule: Self.schedule) { [weak self] intent in
        self?.perform(intent)
    }
    /// Which shortcut each lone key is, as last read from the settings.
    private var shortcuts: [LoneModifierKey: DictationShortcut] = [:]
    private var monitors: [Any] = []
    /// Keys typed in other apps only reach monitors installed with
    /// Accessibility granted. Granted later, they are installed again.
    private var installedTrusted = false
    private var settingsObserver: NSObjectProtocol?

    init(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.dictationLoneKeysDidChange, object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Reads the lone keys again, and listens only while there is one.
    private func refresh() {
        let pairs = DictationShortcut.allCases.compactMap { shortcut in
            AppSettings.dictationLoneKey(for: shortcut).map { ($0, shortcut) }
        }
        shortcuts = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        gesture.keys = Set(shortcuts.keys)
        if shortcuts.isEmpty {
            stopListening()
        } else if monitors.isEmpty {
            startListening()
        }
    }

    private func startListening() {
        installedTrusted = AXIsProcessTrusted()
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown,
                                             .leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
                self?.handle(event)
            },
            NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                self?.handle(event)
                return event
            },
        ].compactMap { $0 }
    }

    private func stopListening() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            if !installedTrusted, AXIsProcessTrusted() {
                // Outside the monitor this event is going through.
                Task { @MainActor [weak self] in
                    guard let self, !installedTrusted, !monitors.isEmpty else { return }
                    stopListening()
                    startListening()
                }
            }
            gesture.handle(.modifiersChanged(keyCode: event.keyCode, flags: event.modifierFlags.rawValue))
        case .keyDown:
            gesture.handle(.keyDown)
        default:
            gesture.handle(.mouseDown)
        }
    }

    /// The same calls as the key combinations make, with the language and
    /// the output of the shortcut set to that key, read on the press.
    private func perform(_ intent: LoneKeyGesture.Intent) {
        switch intent {
        case .press(let key):
            guard let shortcut = shortcuts[key] else { return }
            coordinator?.keyDown(language: shortcut.language, output: shortcut.output)
        case .release:
            coordinator?.keyUp()
        case .cancel:
            coordinator?.cancelHeld()
        }
    }

    private static func schedule(_ delay: TimeInterval,
                                 _ work: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            work()
        }
        return { task.cancel() }
    }
}

extension LoneKeyGesture.Guards {
    static let system = LoneKeyGesture.Guards(
        isTrusted: { AXIsProcessTrusted() },
        isSecureInputOn: { IsSecureEventInputEnabled() },
        // A recorder records while its field editor has the keyboard.
        isRecordingShortcut: {
            (NSApp.keyWindow?.firstResponder as? NSText)?.delegate is KeyboardShortcuts.RecorderCocoa
        }
    )
}
