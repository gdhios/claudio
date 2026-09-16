import CoreAudio

/// The Core Audio taps earlier builds muted the other apps with, while a
/// dictation listened. Claudio pauses the music now and makes no tap, but a
/// public tap outlives the process that made it: an earlier build that
/// crashed mid-dictation left every app silent, until a launch removes it.
/// Every launch still looks, by the name those builds gave their tap.
enum LeftoverMuteTaps {
    /// How those builds named their tap in the system's list.
    static let tapName = "Claudio dictation mute"

    static func remove() {
        guard #available(macOS 14.2, *) else { return }
        let taps = SystemAudioTaps.all().map { (id: $0, name: SystemAudioTaps.name(of: $0)) }
        for id in leftovers(among: taps) {
            AudioHardwareDestroyProcessTap(id)
        }
    }

    /// Which of these taps are Claudio's. Pure, so it can be tested without
    /// touching the system's audio.
    static func leftovers(among taps: [(id: AudioObjectID, name: String?)]) -> [AudioObjectID] {
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
