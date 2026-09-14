import AVFoundation

/// How loud the microphone is, on the 0 to 1 scale the waveform draws.
///
/// The measure is the RMS of a buffer, in decibels, placed between a floor
/// and a ceiling: under the floor is a quiet room and draws nothing, at the
/// ceiling is a voice close to a laptop's microphone. Linear in decibels,
/// because that is how loudness is heard.
enum AudioLevel {
    /// Room noise on a laptop's built-in microphone sits around -55 to -45 dBFS.
    static let floor: Float = -50
    /// Speech at arm's length peaks around -15 to -10 dBFS.
    static let ceiling: Float = -12

    static func normalized(decibels: Float) -> Float {
        min(max((decibels - floor) / (ceiling - floor), 0), 1)
    }

    static func level(of samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = (sum / Float(samples.count)).squareRoot()
        guard rms > 0 else { return 0 }
        return normalized(decibels: 20 * log10(rms))
    }

    /// The first channel is enough: loudness, not stereo, is what's drawn.
    /// A buffer that isn't float, which the microphone tap never hands out,
    /// reads as silence rather than as noise.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        return level(of: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
