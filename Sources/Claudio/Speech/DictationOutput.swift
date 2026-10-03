import Foundation

/// What a dictation becomes once it is said: cleaned up, translated to
/// English, or turned into a prompt. Each shortcut carries its own, which is
/// what makes "speak French, paste corrected English" one keystroke.
///
/// Never a second model call: the output composes its instruction with the
/// dictation preamble `DictationCleanup` already sends, so the transcript is
/// tidied and transformed in the same breath. The instruction itself is the
/// catalog action's, not a new prompt — a translation is a translation
/// wherever it is asked for, custom prompt from Settings included.
///
/// The rawValue is the storage key: add cases, never rename them.
enum DictationOutput: String, CaseIterable, Sendable {
    /// Today's behaviour, and the default: punctuate, drop the hesitations,
    /// keep the language and the words.
    case cleanup
    case translateEN
    case makePrompt

    /// The catalog action whose prompt this output reuses. None for the
    /// cleanup: it is the preamble itself.
    var action: ClaudioAction? {
        switch self {
        case .cleanup: nil
        case .translateEN: .translateEN
        case .makePrompt: .makePrompt
        }
    }

    /// Label in the Dictation settings. The two model-backed ones borrow the
    /// action's own name, so the picker and the palette say the same thing.
    var title: String {
        switch self {
        case .cleanup: loc("Nettoyer", en: "Clean up")
        case .translateEN: ClaudioAction.translateEN.menuTitle
        case .makePrompt: ClaudioAction.makePrompt.menuTitle
        }
    }

    /// What the panel says while the model works: naming the output costs
    /// nothing and a translation taking its time doesn't look like a stuck
    /// cleanup.
    var progressLabel: String {
        switch self {
        case .cleanup: loc("Nettoyage…", en: "Cleaning up…")
        case .translateEN: ClaudioAction.translateEN.progressLabel
        case .makePrompt: ClaudioAction.makePrompt.progressLabel
        }
    }

    /// The system prompt of the one call. `.cleanup` sends the cleanup
    /// prompt, to the byte, edited version included. Anything else sends a
    /// short transcript preamble and then the action's own prompt — and
    /// nothing of the cleanup's.
    ///
    /// It used to glue the whole cleanup prompt in front of the action. That
    /// prompt forbids, at length, exactly what a translation does: "keep the
    /// transcript's language", "never rephrase". A paragraph tried to
    /// arbitrate; the model obeyed whichever side it felt like, and the same
    /// keystroke gave English or French about one time in two. Two
    /// instructions cannot be ranked by asking nicely — so there is only one.
    func systemPrompt(keeping terms: [String],
                      landingIn destination: DictationDestination? = nil) -> String {
        guard let action else {
            return DictationCleanup.systemPrompt(keeping: terms, landingIn: destination)
        }
        return DictationCleanup.systemPrompt(keeping: terms,
                                             landingIn: destination,
                                             base: Self.transcriptPreamble + "\n\n" + action.system)
    }

    /// What the model is sent: always the transcript tagged, never bare.
    /// `.cleanup` uses its own `<transcription>` envelope. The others send it
    /// the way the correction cycle sends a selection: their prompt is the
    /// catalog action's, and it speaks of a text inside `<texte_source>`.
    func userMessage(for raw: String) -> String {
        action == nil ? DictationCleanup.wrappingTranscript(raw) : ClaudioRequest.wrappingSource(raw)
    }

    /// Everything a transforming output needs to know about a dictation, and
    /// not one rule more. It says what the material is and what to do with it
    /// on the way through; what to turn it into is the action's business, and
    /// it is left to say it alone.
    static var transcriptPreamble: String {
        loc("""
            Le texte fourni est une transcription de dictée vocale, pas un texte écrit. \
            Avant d'appliquer les instructions ci-dessous, mets-la au propre pour toi : retire \
            les hésitations et les tics d'oralité, applique les corrections que le locuteur se \
            fait à lui-même (« mardi, non, mercredi » devient « mercredi »), et rends en vrais \
            signes la ponctuation dictée à voix haute (« virgule », « point »). Cette mise au \
            propre ne ressort jamais telle quelle : seul le résultat des instructions ci-dessous \
            est renvoyé.
            """,
            en: """
            The text below is a voice dictation transcript, not written text. Before applying \
            the instructions that follow, tidy it up for yourself: drop the hesitations and \
            verbal tics, apply the corrections the speaker makes to themselves (“Tuesday, no, \
            Wednesday” becomes “Wednesday”), and turn punctuation spoken out loud (“comma”, \
            “period”) into real marks. That tidying never comes out on its own: the answer is \
            the result of the instructions below, and nothing else.
            """)
    }

    /// Output budget in tokens, from the raw transcript's length. An answer
    /// that can run longer than what was said — a rough idea turned into a
    /// whole prompt — would hit the cleanup's ceiling of 4096 and stop
    /// mid-sentence, so the action's own budget applies on top of it. Never
    /// less than the cleanup's: nothing that used to fit gets cut off now.
    func maxTokens(forRawLength length: Int) -> Int {
        let cleanup = DictationCleanup.maxTokens(forRawLength: length)
        guard let budget = action?.budget else { return cleanup }
        return max(cleanup, budget.maxTokens(forLength: length))
    }
}
