import AVFoundation
import Foundation
import Speech

extension SpeechRun {
    /// macOS 14 to 25: `SFSpeechRecognizer`, forced on device, which is also
    /// the fallback whenever the newer transcriber isn't available.
    ///
    /// The order matters: everything that can refuse the dictation is
    /// checked before the microphone is touched, so an unknown language
    /// never opens it.
    func driveLegacy(locale: Locale, contextualStrings: [String]) async {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.supportsOnDeviceRecognition else {
            sink.fail(.languageUnavailable(locale))
            return
        }
        guard recognizer.isAvailable else {
            sink.fail(.recognizer(loc("le moteur de reconnaissance n'est pas disponible",
                                      en: "the recognition engine isn't available")))
            return
        }
        if isCancelled { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        // The speaker's own words made likelier. No vocabulary leaves the
        // request exactly as it was.
        if !contextualStrings.isEmpty {
            request.contextualStrings = Array(contextualStrings.prefix(AppleSpeechEngine.contextualStringsLimit))
        }
        guard let microphone = makeMicrophone() else { return }

        let gate = SpeechGate()
        let sink = self.sink
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    sink.emitFinal(text)
                    gate.open()
                    return
                }
                sink.emitPartial(text)
            }
            guard let error else { return }
            self?.recognizerEnded(with: error)
            gate.open()
        }
        microphone.tap(bufferSize: 2048, levelsTo: sink) { request.append($0) }

        let teardown = {
            microphone.close()
            task.cancel()
            gate.open()
        }
        let onStop = { [weak self] in
            microphone.close()
            request.endAudio()
            self?.armFinalWatchdog(gate)
        }
        switch adopt(teardown: teardown, onStop: onStop) {
        case .running:
            await startAudio(microphone, until: gate)
        case .stopping:
            sink.emitFinal()
        case .cancelled:
            microphone.close()
            task.cancel()
        }
    }
}
