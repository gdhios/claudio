import SwiftUI

/// What one dictation is doing, from the first word heard to the text
/// landing in the app it came from. Observable like `CorrectionSession`, and
/// all the panel reads: the coordinator only ever moves it forward.
@MainActor
final class DictationSession: ObservableObject {
    enum Phase: Equatable {
        /// The microphone is open and the transcript is still growing.
        case listening
        /// The key is released: waiting for the engine's last word.
        case finishing
        /// A model is making the transcript readable.
        case cleaning
        /// The text is on its way back to where it was dictated.
        case pasting
        /// The text exists but the panel stays open: nothing could receive it.
        case done
        /// Nothing was heard. The panel says so, then closes itself.
        case empty
        case error(String)
    }

    /// The language the engine was started in. The session's own, not the
    /// setting's: changing the setting mid-dictation changes nothing here.
    let language: DictationLanguage
    /// The model doing the cleanup, `.raw` when the transcript is pasted as
    /// it was heard.
    let model: ModelChoice

    @Published var phase: Phase = .listening
    /// The transcript as the engine gives it: partial, then final. The
    /// engine always sends the whole text, so this is assigned, never appended to.
    @Published var transcript = ""
    /// The cleaned-up text, as the model streams it.
    @Published var cleanedText = ""
    /// Why the text wasn't cleaned up, shown at the bottom of the panel next
    /// to the model's name. A dictation is never lost: this says what was
    /// pasted instead.
    @Published var note: String?
    /// What stopped the dictation, when one did. The phase carries the
    /// sentence to read; this carries what it was, because a panel that only
    /// knows a sentence can't offer the way out of a missing language.
    /// Written by `fail(with:)` alone, so the two never disagree.
    @Published private(set) var failure: SpeechEngineError?
    @Published var justCopied = false

    init(language: DictationLanguage, model: ModelChoice) {
        self.language = language
        self.model = model
    }

    /// What the panel shows and what gets pasted: the cleaned-up text once
    /// there is one, the transcript until then.
    var finalText: String { cleanedText.isEmpty ? transcript : cleanedText }

    /// True while the panel is waiting on something.
    var isWorking: Bool {
        switch phase {
        case .listening, .finishing, .cleaning, .pasting: true
        case .done, .empty, .error: false
        }
    }

    /// The panel only stays open when the text couldn't be pasted. Copying
    /// it is then the one way it isn't lost.
    var canCopy: Bool {
        switch phase {
        case .done, .error: !finalText.isEmpty
        case .listening, .finishing, .cleaning, .pasting, .empty: false
        }
    }

    /// The dictation stopped: the message goes on screen, the error itself
    /// stays here for whoever can do something about it.
    func fail(with error: SpeechEngineError) {
        failure = error
        phase = .error(error.localizedDescription)
    }

    /// A fragment of the cleanup, as it streams. Unlike a correction, a
    /// dictation lasts one breath: it's published as it comes, with no
    /// buffering to spare the layout.
    func appendCleaned(_ piece: String) { cleanedText += piece }
}
