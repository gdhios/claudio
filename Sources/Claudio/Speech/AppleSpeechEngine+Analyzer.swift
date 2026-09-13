#if canImport(Speech) && compiler(>=6.2)
import AVFoundation
import Foundation
import Speech

/// The macOS 26 path of `AppleSpeechEngine`: `SpeechAnalyzer` fed by the
/// microphone, `SpeechTranscriber` giving back volatile then finalized
/// results.
///
/// The whole file is behind `compiler(>=6.2)`: `SpeechAnalyzer` only exists
/// in the SDK that shipped with that toolchain, and Claudio still builds
/// against older ones, where the `SFSpeechRecognizer` path is the only one.
/// `#available(macOS 26, *)` is the other half: the app still runs on 14.
@available(macOS 26, *)
extension SpeechRun {
    func driveAnalyzer(locale: Locale) async {
        // Claudio downloads nothing by itself: a language that isn't on the
        // machine is an error with instructions, not a background download.
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            sink.fail(.languageUnavailable(locale))
            return
        }
        if isCancelled { return }

        let transcriber = SpeechTranscriber(locale: supported,
                                            transcriptionOptions: [],
                                            reportingOptions: [.volatileResults],
                                            attributeOptions: [])
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            sink.fail(.languageUnavailable(locale))
            return
        }
        if isCancelled { return }

        guard let analysisFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            sink.fail(.recognizer(loc("aucun format audio compatible avec la transcription",
                                      en: "no audio format compatible with transcription")))
            return
        }
        if isCancelled { return }

        let audio = AVAudioEngine()
        let input = audio.inputNode
        let microphoneFormat = input.outputFormat(forBus: 0)
        guard microphoneFormat.sampleRate > 0 else {
            sink.fail(.audioEngine(loc("aucune entrée audio", en: "no audio input")))
            return
        }
        guard let converter = AVAudioConverter(from: microphoneFormat, to: analysisFormat) else {
            sink.fail(.audioEngine(loc("le micro ne peut pas être converti pour la transcription",
                                       en: "the microphone can't be converted for transcription")))
            return
        }

        let (inputStream, inputSink) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let gate = SpeechGate()
        let sink = self.sink

        // The transcriber reports two kinds of result: volatile ones, which
        // replace the tail of the text, and finalized ones, which append to
        // it. The contract is the whole session's text every time, so the
        // finalized part is kept here and the volatile part glued behind it.
        let collector = Task { [weak self] in
            var finalized = AttributedString()
            do {
                for try await result in transcriber.results {
                    if result.isFinal {
                        finalized.append(result.text)
                        sink.emitPartial(String(finalized.characters))
                    } else {
                        var preview = finalized
                        preview.append(result.text)
                        sink.emitPartial(String(preview.characters))
                    }
                }
                sink.emitFinal()
            } catch {
                // A cancelled run says nothing more: the error is the one
                // the teardown caused.
                if self?.isCancelled != false {
                    // nothing to report
                } else if self?.isStopping == true {
                    sink.emitFinal()
                } else {
                    sink.fail(.recognizer(error.localizedDescription))
                }
            }
            gate.open()
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: microphoneFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, with: converter, to: analysisFormat) else { return }
            inputSink.yield(AnalyzerInput(buffer: converted))
        }

        let closeMicrophone = {
            input.removeTap(onBus: 0)
            audio.stop()
            inputSink.finish()
        }
        let teardown = {
            closeMicrophone()
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
            gate.open()
        }
        let onStop = {
            closeMicrophone()
            // The analyzer finishes what it has, the results stream ends,
            // and the collector emits the final. The watchdog is there for
            // the case where it never does.
            Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
            Task {
                try? await Task.sleep(for: AppleSpeechEngine.finalTimeout)
                sink.emitFinal()
                gate.open()
            }
        }
        guard adopt(teardown: teardown, onStop: onStop) else {
            closeMicrophone()
            collector.cancel()
            return
        }

        do {
            try await analyzer.start(inputSequence: inputStream)
            audio.prepare()
            try audio.start()
        } catch {
            sink.fail(.audioEngine(error.localizedDescription))
            return
        }
        if isCancelled { return }
        await gate.wait()
    }

    /// The microphone rarely speaks the format the transcriber wants; this
    /// is the one place the two meet. A buffer that can't be converted is
    /// dropped rather than sent malformed: a hole in the sound costs a word,
    /// a bad buffer costs the session.
    private static func convert(_ buffer: AVAudioPCMBuffer,
                                with converter: AVAudioConverter,
                                to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        // The block runs synchronously inside `convert`, on this thread,
        // and is asked for the one buffer we already hold: `nonisolated`
        // says so, since the audio types carry no `Sendable` of their own.
        nonisolated(unsafe) let source = buffer
        nonisolated(unsafe) var offered = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if offered {
                status.pointee = .noDataNow
                return nil
            }
            offered = true
            status.pointee = .haveData
            return source
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
#endif
