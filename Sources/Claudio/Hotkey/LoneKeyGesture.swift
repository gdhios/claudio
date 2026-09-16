import Foundation

/// A lone modifier key as a dictation shortcut, with the gesture of the key
/// combinations: held, it listens while it is down; tapped, it goes
/// hands-free. The catch is that the key is also half of every combination
/// typed with it — on AZERTY, ⌥⇧L types "|" and ⌥( types "{" — so a press
/// only becomes a dictation once the key has stayed down alone for a moment,
/// and a dictation that turns out to be a combination is cancelled.
///
/// Pure: it is fed what the keyboard and the mouse did, schedules its delay
/// through a closure and says what the dictation should do. `LoneKeyMonitor`
/// plugs it into real events.
@MainActor
final class LoneKeyGesture {
    enum Event: Equatable {
        /// A modifier key went down or up: its key code, and the raw modifier
        /// flags right after, device-dependent bits included.
        case modifiersChanged(keyCode: UInt16, flags: UInt)
        /// Any other key went down.
        case keyDown
        /// A mouse button went down.
        case mouseDown
        /// The arming delay ran out.
        case delayElapsed
    }

    /// What the dictation is told: one `DictationCoordinator` call each.
    enum Intent: Equatable {
        /// `keyDown(language:output:)`, for the shortcut set to this key.
        case press(LoneModifierKey)
        /// `keyUp()`.
        case release
        /// `cancelHeld()`: it was a combination, not a dictation.
        case cancel
    }

    /// When a key going down isn't listened to at all. Read on each press.
    @MainActor
    struct Guards {
        /// Without Accessibility, keys typed in other apps never arrive, and
        /// every combination would look like a lone press.
        var isTrusted: @MainActor () -> Bool
        /// A password field hides the keystrokes the same way.
        var isSecureInputOn: @MainActor () -> Bool
        /// A shortcut recorder has the keyboard in Settings: the key is being
        /// recorded, not used.
        var isRecordingShortcut: @MainActor () -> Bool
    }

    /// Runs `work` after `delay` seconds, unless the closure handed back is
    /// called first.
    typealias Schedule = @MainActor (_ delay: TimeInterval,
                                     _ work: @escaping @MainActor () -> Void) -> @MainActor () -> Void

    /// How long the key stays down alone before it is a dictation: time
    /// enough for the second key of a combination, too little to lose the
    /// first word.
    static let armingDelay: TimeInterval = 0.15

    private enum State {
        case idle
        /// Down alone, the delay running.
        case arming(LoneModifierKey)
        /// The dictation was told of the press; the key is still down.
        case held(LoneModifierKey)
        /// Dropped or cancelled, the key still down: its release ends nothing.
        case ignoring(LoneModifierKey)
    }

    /// The keys the dictation shortcuts are set to.
    var keys: Set<LoneModifierKey>

    private let guards: Guards
    private let schedule: Schedule
    private let emit: @MainActor (Intent) -> Void

    private var state = State.idle
    private var cancelDelay: (@MainActor () -> Void)?

    init(keys: Set<LoneModifierKey>,
         guards: Guards,
         schedule: @escaping Schedule,
         emit: @escaping @MainActor (Intent) -> Void) {
        self.keys = keys
        self.guards = guards
        self.schedule = schedule
        self.emit = emit
    }

    func handle(_ event: Event) {
        switch (state, event) {
        case (.idle, .modifiersChanged(let keyCode, let flags)):
            armIfAlone(keyCode: keyCode, flags: flags)

        case (.arming(let key), .modifiersChanged(let keyCode, let flags)):
            if Self.isRelease(of: key, keyCode: keyCode, flags: flags) {
                // Up within the delay with nothing else pressed: a tap, which
                // the coordinator locks hands-free.
                stopDelay()
                state = .idle
                emit(.press(key))
                emit(.release)
            } else if key.othersAreDown(in: flags) {
                drop(key)
            }
        case (.arming(let key), .keyDown), (.arming(let key), .mouseDown):
            // Nothing was started, so nothing is cancelled: no panel, no
            // microphone, the music untouched.
            drop(key)
        case (.arming(let key), .delayElapsed):
            cancelDelay = nil
            state = .held(key)
            emit(.press(key))

        case (.held(let key), .modifiersChanged(let keyCode, let flags)):
            if Self.isRelease(of: key, keyCode: keyCode, flags: flags) {
                state = .idle
                emit(.release)
            } else if key.othersAreDown(in: flags) {
                state = .ignoring(key)
                emit(.cancel)
            }
        case (.held(let key), .keyDown), (.held(let key), .mouseDown):
            state = .ignoring(key)
            emit(.cancel)

        case (.ignoring(let key), .modifiersChanged(let keyCode, let flags)):
            if Self.isRelease(of: key, keyCode: keyCode, flags: flags) { state = .idle }

        default:
            // Hands-free the key is up and idle: typing is typing. And a delay
            // running out after its press ended has nothing left to start.
            break
        }
    }

    /// A key a shortcut is set to went down with no other modifier: the
    /// delay starts, unless the key can't be told from a combination here.
    private func armIfAlone(keyCode: UInt16, flags: UInt) {
        guard let key = LoneModifierKey(keyCode: keyCode), keys.contains(key),
              key.isDown(in: flags), !key.othersAreDown(in: flags),
              guards.isTrusted(), !guards.isSecureInputOn(), !guards.isRecordingShortcut()
        else { return }
        state = .arming(key)
        cancelDelay = schedule(Self.armingDelay) { [weak self] in
            self?.handle(.delayElapsed)
        }
    }

    private func drop(_ key: LoneModifierKey) {
        stopDelay()
        state = .ignoring(key)
    }

    private func stopDelay() {
        cancelDelay?()
        cancelDelay = nil
    }

    /// The key came up: its own event without its own bit — or, should that
    /// event have gone missing, no key of its pair down at all.
    private static func isRelease(of key: LoneModifierKey, keyCode: UInt16, flags: UInt) -> Bool {
        (keyCode == key.keyCode && !key.isDown(in: flags)) || key.pairIsUp(in: flags)
    }
}
