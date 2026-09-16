import Foundation

/// What saying an instruction does to the free action's panel. Injected as
/// one value, like `PasteService`, so the whole gesture is playable without a
/// screen, a selection or a network.
@MainActor
struct SpokenInstructionPanel {
    /// A tap: the instruction gets typed, exactly as the shortcut has always
    /// done. Only used when nothing was opened on the press.
    var type: @MainActor () -> Void
    /// A hold: the free action's own panel opens on the selection, already
    /// listening, and hands back the session the words land in. `nil` when
    /// nothing opened — without Accessibility there is nothing to transform.
    var listen: @MainActor () -> CorrectionSession?
    /// The instruction, as it was heard: the usual free action carries on
    /// from there, in the panel that is already up.
    var run: @MainActor (String) -> Void
    /// Takes the panel off the screen, once it has said what it had to say.
    var close: @MainActor () -> Void

    /// The real panel: the correction coordinator opens it, streams into it
    /// and closes it — this only says when.
    static func freeAction(_ coordinator: CorrectionCoordinator) -> SpokenInstructionPanel {
        SpokenInstructionPanel(
            type: { [weak coordinator] in coordinator?.triggerFreeAction() },
            listen: { [weak coordinator] in coordinator?.beginSpokenInstruction() ?? nil },
            run: { [weak coordinator] instruction in coordinator?.runSpokenInstruction(instruction) },
            close: { [weak coordinator] in coordinator?.dismiss() }
        )
    }
}

/// Saying the instruction instead of typing it. The free action's shortcut
/// carries both gestures, as dictation's does: tapped it opens the field
/// where the instruction is typed, held it opens the microphone and the
/// instruction is spoken, then applied to the selection the press captured.
///
/// `DictationCoordinator`'s counterpart — same engine, same vocabulary, same
/// silence around it — except the words are an instruction, not a text: they
/// are used as heard, no model is asked to tidy them, and what streams back
/// is an ordinary free action.
///
/// Everything that touches the outside world arrives through `init`: the
/// engine, the panel, the microphone, the sound, the clock.
@MainActor
final class SpokenInstructionCoordinator {
    /// What the key going down started, and so what its release has to do.
    private enum Press {
        /// The microphone is open on this session: released late the
        /// instruction was spoken, released early it goes back to the field.
        case listening(CorrectionSession)
        /// Nothing was opened, for lack of a microphone: the release does
        /// what the shortcut has always done, or asks for the permission.
        case withoutMicrophone
        /// Nothing left to finish: no press under way, or one already ended.
        case none
    }

    private let engine: SpeechEngine
    private let panel: SpokenInstructionPanel
    private let language: @MainActor () -> DictationLanguage
    private let vocabulary: @MainActor () -> DictationVocabulary
    private let microphone: MicrophoneGate
    private let silencer: OutputSilencer
    private let mutesOutput: @MainActor () -> Bool
    private let durations: DictationCoordinator.MessageDurations
    private let now: @MainActor () -> Date

    private var press = Press.none
    /// The session being listened into, kept while the panel says why it
    /// heard nothing too: it is what tells a message still on screen from
    /// one another action has since replaced.
    private var session: CorrectionSession?
    private var pressedAt = Date.distantPast

    /// The task that listens then hands the instruction over: cancelled by
    /// the panel going away and by the next press.
    private(set) var cycle: Task<Void, Never>?
    /// The task asking for the microphone, on a hold only. `nil` whenever
    /// the permissions are already there.
    private(set) var permission: Task<Void, Never>?

    init(engine: SpeechEngine,
         panel: SpokenInstructionPanel,
         language: @escaping @MainActor () -> DictationLanguage = {
             AppSettings.dictationPrimaryLanguage
         },
         vocabulary: @escaping @MainActor () -> DictationVocabulary = {
             DictationVocabulary(parsing: AppSettings.dictationVocabulary)
         },
         microphone: MicrophoneGate = .system,
         silencer: OutputSilencer = .system,
         mutesOutput: @escaping @MainActor () -> Bool = { AppSettings.dictationMutesOutput },
         durations: DictationCoordinator.MessageDurations = .standard,
         now: @escaping @MainActor () -> Date = Date.init) {
        self.engine = engine
        self.panel = panel
        self.language = language
        self.vocabulary = vocabulary
        self.microphone = microphone
        self.silencer = silencer
        self.mutesOutput = mutesOutput
        self.durations = durations
        self.now = now
    }

    // MARK: - The gesture

    /// Key down: the panel opens on the selection with the microphone
    /// already listening. Which gesture it was is only known on the release,
    /// so the words are caught from the first instant rather than from the
    /// moment a hold becomes certain.
    func keyDown() {
        cancel()  // idempotent: a press during a cycle starts a fresh one
        pressedAt = now()

        // Without the microphone, the key keeps today's behaviour to the
        // letter: nothing opens on the press, and the release types the
        // instruction or asks for the permission.
        guard microphone.isGranted() else {
            press = .withoutMicrophone
            return
        }
        // The panel captures the selection itself, before showing anything:
        // what gets transformed is what was selected when the key went down.
        guard let session = panel.listen() else { return }
        press = .listening(session)
        self.session = session

        // Read on the press, like the language: the engine, the
        // replacements and the words all get this one, whatever Settings
        // says by the time the key comes up.
        let vocabulary = self.vocabulary()
        // Music talking over the voice is what makes an instruction hard to
        // hear: the other apps go quiet for as long as the microphone listens.
        if mutesOutput() { silencer.silence() }
        cycle = Task { [weak self] in
            await self?.listen(session: session, vocabulary: vocabulary)
        }
    }

    /// Key up: held, the microphone closes and the engine gets to say its
    /// last word. Tapped, the instruction goes back to being typed.
    func keyUp() {
        let held = now().timeIntervalSince(pressedAt) >= DictationCoordinator.shortPressThreshold
        switch press {
        case .listening(let session):
            guard held else {
                // A tap: the microphone closes on a word nobody asked for,
                // and the panel — the same one, over the same selection —
                // hands back its field.
                cancel()
                session.typeInstructionInstead()
                return
            }
            finishListening(session)
        case .withoutMicrophone:
            press = .none
            guard held else {
                panel.type()
                return
            }
            // Held to speak on a Mac that has never been asked: the prompts
            // are modal and the key is long released by the time they are
            // answered, so this press asks and the next one speaks. Same
            // bargain as dictation's.
            askForTheMicrophone()
        case .none:
            break
        }
    }

    /// The panel went away — Esc, another shortcut, the free action starting
    /// over: whatever was listening stops, and the sound comes back with it.
    /// Idempotent, and never closes anything itself: it is called from the
    /// closing.
    func cancel() {
        press = .none
        cycle?.cancel()
        cycle = nil
        // The prompts can't be taken back, but the explanation that follows
        // them can: a press that starts a new chain drops the old one rather
        // than letting two alerts pile up on the same refusal.
        permission?.cancel()
        permission = nil
        // Only an instruction under way has a microphone to close.
        if session != nil { engine.cancel() }
        // Every way out ends here or in `finishListening(_:)`: the sound
        // comes back whatever happened. Harmless when nothing was silenced.
        silencer.restore()
        session = nil
    }

    private func askForTheMicrophone() {
        permission = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let granted = await microphone.request()
            guard !Task.isCancelled, !granted else { return }
            microphone.showExplanation()
        }
    }

    /// The key came up on a hold: the microphone closes and the engine gets
    /// to say its last word.
    private func finishListening(_ session: CorrectionSession) {
        press = .none
        session.listeningEnded = true
        engine.stop()
        // After the microphone has closed, so the returning sound is never
        // heard as part of the instruction.
        silencer.restore()
    }

    // MARK: - The cycle

    private func listen(session: CorrectionSession, vocabulary: DictationVocabulary) async {
        // Cancelled between the press and the first turn of the loop: the
        // microphone must not even open.
        guard self.session === session else { return }

        for await event in engine.start(locale: language().locale,
                                        contextualStrings: vocabulary.terms) {
            guard self.session === session else { return }
            switch event {
            case .partial(let text), .final(let text):
                // Straight into the field the instruction would have been
                // typed in: one panel, one place where it reads.
                session.instruction = text
            case .level(let level):
                session.levels = session.levels.adding(level)
            case .failed(let error):
                // The panel stays up to be read; the sound doesn't wait for it.
                silencer.restore()
                giveUp(reason: error.localizedDescription, session: session)
                return
            }
        }
        // The stream ends after the final, and on a cancellation: only the
        // first of the two still has an instruction to run.
        guard self.session === session, !Task.isCancelled else { return }
        finish(session: session, vocabulary: vocabulary)
    }

    /// From the last words heard to the free action starting: fix the
    /// vocabulary, then hand the instruction over as it was said. No model
    /// is asked to clean it up — an instruction is read, not pasted.
    private func finish(session: CorrectionSession, vocabulary: DictationVocabulary) {
        // The stream is over, so is the microphone: an engine that stopped
        // by itself never gave the sound back.
        silencer.restore()
        let heard = session.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else {
            // A silence, a key held on nothing: said rather than run.
            giveUp(reason: nil, session: session)
            return
        }
        let instruction = vocabulary.applyingReplacements(to: heard)
        session.instruction = instruction
        // The panel is the correction coordinator's alone from here: it
        // streams the answer into it and closes it.
        self.session = nil
        cycle = nil
        panel.run(instruction)
    }

    /// Nothing to run: the panel says so — a silence, or the reason the
    /// microphone gave — then takes itself off the screen, as a dictation
    /// that heard nothing does.
    private func giveUp(reason: String?, session: CorrectionSession) {
        press = .none
        cycle = nil
        session.phase = .instructionNotHeard(reason: reason)
        let delay = reason == nil ? durations.empty : durations.failure
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            // Another action may own the panel by now: closing it would
            // take away a window nobody asked to close.
            guard let self, self.session === session else { return }
            self.session = nil
            panel.close()
        }
    }
}
