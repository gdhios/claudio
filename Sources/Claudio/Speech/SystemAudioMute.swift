import CoreAudio
import Foundation

/// Every other app's sound, silenced before it reaches the output, while a
/// dictation listens.
///
/// A Core Audio process tap on all processes, with the "muted" behavior: the
/// tapped audio is never sent to the hardware. It works whatever the output
/// is — a USB interface or a DJ controller that has no volume or mute of its
/// own, which the device-level mute can't touch — and asks for no permission,
/// since nothing is ever read from the tap. Destroying the tap brings the
/// sound back.
///
/// The tap is public on purpose. Measured on macOS 26.6: a public tap
/// survives its process being killed, and every app stays silent. A private
/// one can't be found from the next launch, so a crash would leave nothing to
/// clean. Public, it carries Claudio's name, and every launch removes the
/// ones a crash left behind. The watchdog covers the rest: a tap is never
/// kept longer than a dictation can last.
@MainActor
final class SystemAudioMute {
    static let shared = SystemAudioMute()

    /// How Claudio's tap is recognized in the system's list.
    nonisolated static let tapName = "Claudio dictation mute"
    /// Longer than any dictation can listen: a locked one finishes by itself
    /// at its limit, and the margin covers the short press that locked it
    /// and a timer that fires late. Past it, the sound comes back on its own.
    static let longestSilence: Duration = DictationCoordinator.longestLockedDictation + .seconds(60)

    private var tap: AudioObjectID?
    private var watchdog: Task<Void, Never>?

    func silence() {
        guard tap == nil, !PreviewRun.isActive else { return }
        guard #available(macOS 14.2, *) else { return }
        Self.removeLeftovers()

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = Self.tapName
        description.muteBehavior = .muted
        description.isPrivate = false
        var created = AudioObjectID(kAudioObjectUnknown)
        // A tap that can't be made costs the silence, never the dictation.
        guard AudioHardwareCreateProcessTap(description, &created) == noErr,
              created != kAudioObjectUnknown else { return }
        tap = created

        watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.longestSilence)
            guard !Task.isCancelled else { return }
            self?.restore()
        }
    }

    /// Idempotent: called on every way out of a dictation, muted or not.
    func restore() {
        watchdog?.cancel()
        watchdog = nil
        guard let tap else { return }
        self.tap = nil
        if #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(tap)
        }
    }

    /// Claudio's taps still in the system's list: left there by a crash,
    /// since a running dictation removes its own. Called at launch and before
    /// each new silence.
    static func removeLeftovers() {
        guard #available(macOS 14.2, *) else { return }
        let taps = SystemAudioTaps.all().map { (id: $0, name: SystemAudioTaps.name(of: $0)) }
        for id in leftovers(among: taps) {
            AudioHardwareDestroyProcessTap(id)
        }
    }

    /// Which of these taps are Claudio's. Pure, so it can be tested without
    /// silencing anything.
    nonisolated static func leftovers(among taps: [(id: AudioObjectID, name: String?)]) -> [AudioObjectID] {
        taps.filter { $0.name == tapName }.map(\.id)
    }
}

/// The two Core Audio reads the sweep needs: the public taps, and a tap's name.
@available(macOS 14.2, *)
private enum SystemAudioTaps {
    static func all() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTapList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: kAudioObjectUnknown,
                                  count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func name(of tap: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyDescription,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var description: Unmanaged<CATapDescription>?
        var size = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &description) == noErr else { return nil }
        return description?.takeRetainedValue().name
    }
}
