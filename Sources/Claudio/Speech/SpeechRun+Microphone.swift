import AVFoundation
import Foundation

/// The microphone, the same on both recognizer paths: found, tapped, turned
/// on, closed. Only what is done with each buffer is a path's own.
extension SpeechRun {
    /// The microphone as a run holds it: the engine whose input it is, and
    /// the format that input speaks. It hears nothing before `start()`, and
    /// `close()` can come any number of times — the stop, then the teardown.
    struct Microphone {
        let audio: AVAudioEngine
        let input: AVAudioInputNode
        let format: AVAudioFormat

        /// Every buffer to `feed`, its loudness to the waveform first. The
        /// buffer size stays each path's own: it sets how often the
        /// waveform moves.
        func tap(bufferSize: AVAudioFrameCount,
                 levelsTo sink: TranscriptSink,
                 feed: @escaping (AVAudioPCMBuffer) -> Void) {
            input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
                sink.emitLevel(AudioLevel.level(of: buffer))
                feed(buffer)
            }
        }

        func start() throws {
            audio.prepare()
            try audio.start()
        }

        func close() {
            input.removeTap(onBus: 0)
            audio.stop()
        }
    }

    /// The microphone, or `nil` once the run has failed for want of one: a
    /// Mac with no audio input reports a format of zero hertz.
    func makeMicrophone() -> Microphone? {
        let audio = AVAudioEngine()
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            sink.fail(.audioEngine(loc("aucune entrée audio", en: "no audio input")))
            return nil
        }
        return Microphone(audio: audio, input: input, format: format)
    }

    /// Turns the microphone on, then waits for the run's last word.
    func startAudio(_ microphone: Microphone, until gate: SpeechGate) async {
        do {
            try microphone.start()
        } catch {
            sink.fail(.audioEngine(error.localizedDescription))
            return
        }
        if isCancelled { return }
        await gate.wait()
    }
}
