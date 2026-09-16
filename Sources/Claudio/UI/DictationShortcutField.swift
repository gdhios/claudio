import AppKit
import KeyboardShortcuts
import SwiftUI

/// A dictation shortcut's field in Settings. Key combinations record in the
/// library's own recorder, exactly as every other shortcut's do. A modifier
/// key pressed and released alone records too when it is a right-hand one,
/// and `LoneKeyField` then shows it in place of the recorder, which only
/// comes back to record again.
struct DictationShortcutField: NSViewRepresentable {
    let shortcut: DictationShortcut

    func makeNSView(context: Context) -> DictationShortcutFieldView {
        DictationShortcutFieldView(shortcut: shortcut)
    }

    func updateNSView(_ view: DictationShortcutFieldView, context: Context) {}
}

final class DictationShortcutFieldView: NSView {
    private let shortcut: DictationShortcut
    private let recorder: KeyboardShortcuts.RecorderCocoa
    private let loneKeyField = LoneKeyField()
    private var recording = LoneKeyRecording()
    /// Watches the modifiers while the recorder records.
    private var keyMonitor: Any?
    private var responderObservation: NSKeyValueObservation?
    private var settingsObserver: NSObjectProtocol?

    init(shortcut: DictationShortcut) {
        self.shortcut = shortcut
        // Whatever the recorder stores — a combination, or nothing once
        // cleared — ends the lone key: a shortcut is one or the other.
        recorder = KeyboardShortcuts.RecorderCocoa(for: shortcut.name) { _ in
            AppSettings.setDictationLoneKey(nil, for: shortcut)
        }
        super.init(frame: recorder.frame)
        for field in [recorder, loneKeyField] as [NSView] {
            field.frame = bounds
            field.autoresizingMask = [.width, .height]
            addSubview(field)
        }
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        loneKeyField.onClick = { [weak self] in self?.recordAgain() }
        loneKeyField.onClear = { AppSettings.setDictationLoneKey(nil, for: shortcut) }
        showCurrentKey()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { recorder.intrinsicContentSize }

    /// The recorder records while its field editor has the keyboard.
    private var isRecording: Bool {
        (window?.firstResponder as? NSText)?.delegate === recorder
    }

    /// The lone key in place of the recorder — unless there is none, or the
    /// recorder is recording. A preview shows its own, never this Mac's.
    private func showCurrentKey() {
        let key = PreviewRun.isActive
            ? PreviewRun.dictationLoneKeys[shortcut]
            : AppSettings.dictationLoneKey(for: shortcut)
        let showsKey = key != nil && !isRecording
        loneKeyField.stringValue = key?.title ?? ""
        loneKeyField.isHidden = !showsKey
        recorder.isHidden = showsKey
    }

    private func recordAgain() {
        loneKeyField.isHidden = true
        recorder.isHidden = false
        window?.makeFirstResponder(recorder)
    }

    /// Everything this field listens to lives while it is on screen.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopWatchingKeys()
        responderObservation = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
        guard let window else { return }

        responderObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            // Once the recorder has finished taking the keyboard: it installs
            // its own key monitor then, which swallows the keys it records,
            // and monitors run newest first. This one has to come after it.
            Task { @MainActor [weak self] in self?.recordingMayHaveChanged() }
        }
        // A key set in the other row can be taken from this one.
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.dictationLoneKeysDidChange, object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showCurrentKey() }
        }
        showCurrentKey()
    }

    private func recordingMayHaveChanged() {
        if isRecording {
            startWatchingKeys()
        } else {
            stopWatchingKeys()
        }
        showCurrentKey()
    }

    private func startWatchingKeys() {
        guard keyMonitor == nil else { return }
        recording = LoneKeyRecording()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.watch(event)
            return event
        }
    }

    private func stopWatchingKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func watch(_ event: NSEvent) {
        guard event.type == .flagsChanged else {
            recording.keyDown()
            return
        }
        switch recording.modifiersChanged(keyCode: event.keyCode, flags: event.modifierFlags.rawValue) {
        case .recorded(let key):
            // The key replaces the combination, stored as removed rather than
            // reset: a default combination must not come back with it.
            AppSettings.setDictationLoneKey(key, for: shortcut)
            KeyboardShortcuts.setShortcut(nil, for: shortcut.name)
            window?.makeFirstResponder(nil)
        case .refused:
            NSSound.beep()
        case nil:
            break
        }
    }
}
