import Foundation

/// One audio source plus one recognizer. The coordinator knows nothing else
/// about dictation: this contract is what lets a downloadable engine arrive
/// later without touching it, and what lets the tests replay a fixed list of
/// events instead of opening a microphone.
protocol SpeechEngine: AnyObject, Sendable {
    /// Opens the microphone and starts recognition, leaning towards
    /// `contextualStrings`: the vocabulary's terms, names and jargon the
    /// recognizer would otherwise spell its own way. An empty list asks for
    /// plain recognition. The stream ends after `.final` or `.failed`.
    func start(locale: Locale, contextualStrings: [String]) -> AsyncStream<TranscriptEvent>
    /// Closes the microphone; the engine still emits its `.final`, then ends
    /// the stream.
    func stop()
    /// Cancels without a final: the stream ends with no further event.
    func cancel()
}
