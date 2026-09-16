import AppKit
import Combine
import XCTest
@testable import Claudio

/// The dictation cycle, from the key going down to the text landing in the
/// app — with no microphone, no network, no pasteboard, no keystroke and no
/// window. The engine replays a fixed list of events, the model is a fake
/// client, the paste is a closure that only remembers what it was handed,
/// and the panel is never built.
@MainActor
final class DictationCoordinatorTests: XCTestCase {

    // MARK: - The whole cycle

    /// What a held press does: the partials show up while the key is down,
    /// the release closes the microphone, the model makes the transcript
    /// readable, and it's the cleaned-up text that gets pasted.
    func testAHeldPressPastesTheCleanedUpText() async throws {
        let bench = Bench()
        let coordinator = bench.coordinator

        coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(coordinator.session)
        let log = bench.watch(session)
        await bench.settle { session.transcript == "bonjour" }
        XCTAssertEqual(session.phase, .listening)
        XCTAssertEqual(bench.panels, 1)

        bench.hold(for: 1)
        coordinator.keyUp()
        XCTAssertEqual(bench.engine.stops, 1)
        await coordinator.cycle?.value

        XCTAssertEqual(log.phases, [.listening, .finishing, .cleaning, .pasting])
        XCTAssertEqual(session.cleanedText, "Bonjour.")
        XCTAssertEqual(bench.pasted, ["Bonjour."])
        XCTAssertNil(session.note)
        // Pasted: the panel has nothing left to say and closes itself.
        XCTAssertNil(coordinator.session)
    }

    /// The microphone's loudness goes to the waveform, newest last, and
    /// leaves the transcript alone.
    func testLevelsFeedTheWaveformNotTheTranscript() async throws {
        let bench = Bench(events: [.level(0.25), .partial("bon"), .level(0.75), .final("bon")])
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.settle { session.levels.values.last == 0.75 }
        XCTAssertEqual(Array(session.levels.values.suffix(2)), [0.25, 0.75])
        XCTAssertEqual(session.transcript, "bon")
    }

    // MARK: - What was playing

    /// Music talking over the voice is what makes dictation hard: whatever
    /// plays is paused while the key is down, and resumed on release — after
    /// the microphone has closed, so the music coming back is never heard as
    /// speech, and before the paste, which doesn't need silence.
    func testWhatPlaysPausesWhileTheKeyIsHeldAndResumesOnRelease() async {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.media.commands == [.pause] }
        XCTAssertEqual(bench.media.commands, [.pause])

        bench.hold(for: 1)
        bench.coordinator.keyUp()
        XCTAssertEqual(bench.media.commands, [.pause, .play])
        XCTAssertEqual(bench.media.microphoneClosesAtResume, [1])
        XCTAssertTrue(bench.pasted.isEmpty)

        await bench.coordinator.cycle?.value
        XCTAssertEqual(bench.pasted, ["Bonjour."])
        XCTAssertEqual(bench.media.commands, [.pause, .play])
        XCTAssertEqual(bench.media.reads, 1)
    }

    /// Nothing playing, nothing sent: above all no play at the end, which
    /// would start music that was paused before anyone dictated.
    func testNothingPlayingSendsNoCommandAtAll() async {
        let bench = Bench(playing: false)
        await bench.dictate()
        XCTAssertEqual(bench.media.reads, 1)
        XCTAssertEqual(bench.media.commands, [])
    }

    /// The microphone never waits for the state: it opens on the press, the
    /// read still out, and the pause follows whenever the answer comes.
    func testTheMicrophoneOpensWithoutWaitingForTheRead() async {
        let bench = Bench(readsWait: true)
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.engine.starts == 1 && bench.media.reads == 1 }
        XCTAssertEqual(bench.engine.starts, 1)
        XCTAssertEqual(bench.media.commands, [])

        bench.media.answerRead()
        await bench.pauser.read?.value
        XCTAssertEqual(bench.media.commands, [.pause])
        bench.coordinator.escape()
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// Over before the state was read — Esc on the spot: the answer finds the
    /// microphone closed, and nothing is paused for it. Music that went on
    /// playing needs no resume.
    func testAReadAnsweredAfterTheEndPausesNothing() async {
        let bench = Bench(readsWait: true)
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.engine.starts == 1 && bench.media.reads == 1 }
        let read = bench.pauser.read
        bench.coordinator.escape()

        bench.media.answerRead()
        await read?.value
        XCTAssertEqual(bench.media.reads, 1)
        XCTAssertEqual(bench.media.commands, [])
    }

    /// Same for a microphone that fails the moment it opens.
    func testAReadAnsweredAfterAnImmediateFailurePausesNothing() async {
        let bench = Bench(events: [.failed(.microphoneDenied)], readsWait: true)
        bench.coordinator.keyDown(language: .frFR)
        let read = bench.pauser.read
        await bench.coordinator.cycle?.value

        bench.media.answerRead()
        await read?.value
        XCTAssertEqual(bench.media.commands, [])
    }

    /// A late answer belongs to the press that asked. The next dictation has
    /// its own read, and only that one pauses anything.
    func testALateReadNeverPausesForTheNextDictation() async {
        let bench = Bench(readsWait: true)
        bench.coordinator.keyDown(language: .frFR)
        let first = bench.pauser.read
        await bench.settle { bench.engine.starts == 1 && bench.media.reads == 1 }
        bench.coordinator.escape()
        bench.coordinator.keyDown(language: .frFR)
        let second = bench.pauser.read
        await bench.settle { bench.engine.starts == 2 && bench.media.reads == 2 }

        bench.media.answerRead()
        await first?.value
        XCTAssertEqual(bench.media.commands, [])

        bench.media.answerRead()
        await second?.value
        XCTAssertEqual(bench.media.commands, [.pause])
        bench.coordinator.escape()
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// Esc resumes what the press paused, and a second one — or the panel
    /// closing, or quitting, which all end in the same place — resumes
    /// nothing more.
    func testEscapeResumesExactlyOnce() async {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.media.commands == [.pause] }

        bench.coordinator.escape()
        bench.coordinator.escape()
        bench.coordinator.dismiss()
        XCTAssertEqual(bench.media.commands, [.pause, .play])
        XCTAssertEqual(bench.media.microphoneClosesAtResume, [1])
    }

    /// A tap locks the dictation rather than dropping it: still listening,
    /// so the music stays paused with the key up.
    func testATapKeepsTheMusicPausedWhileItListens() async throws {
        let bench = Bench()
        try await bench.lock()
        XCTAssertEqual(bench.media.commands, [.pause])
    }

    /// A dictation that fails keeps its panel up for a few seconds to be
    /// read; the music doesn't wait for it to close, and its closing resumes
    /// nothing more.
    func testAFailureResumesAtOnceAndOnlyOnce() async throws {
        let bench = Bench(durations: .init(empty: .milliseconds(50), failure: .milliseconds(50)))
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.settle { bench.media.commands == [.pause] }

        bench.engine.say(.failed(.recognizer("timeout")))
        await bench.cycleEnds()
        XCTAssertEqual(session.phase,
                       .error(SpeechEngineError.recognizer("timeout").localizedDescription))
        XCTAssertEqual(bench.media.commands, [.pause, .play])

        await bench.wait { bench.coordinator.session == nil }
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// Nothing heard is an end like any other: resumed once, not again when
    /// "Nothing heard" leaves the screen.
    func testNothingHeardResumesOnce() async throws {
        let bench = Bench(events: [.partial("  "), .final("   ")],
                          durations: .init(empty: .milliseconds(50), failure: .milliseconds(50)))
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.finish()
        XCTAssertEqual(session.phase, .empty)
        XCTAssertEqual(bench.media.commands, [.pause, .play])

        await bench.wait { bench.coordinator.session == nil }
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// A press during a dictation starts a fresh one: the first resumes what
    /// it paused, and the second reads the state for itself.
    func testANewPressResumesThenReadsAgain() async {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.media.commands == [.pause] }

        bench.coordinator.keyDown(language: .enUS)
        XCTAssertEqual(bench.media.commands, [.pause, .play])
        await bench.pauser.read?.value
        XCTAssertEqual(bench.media.reads, 2)
        XCTAssertEqual(bench.media.commands, [.pause, .play, .pause])
    }

    /// Switched off in Settings: the state isn't even read, and nothing is
    /// ever sent.
    func testWithTheSettingOffNothingIsReadNorSent() async {
        let bench = Bench(pausesMedia: false)
        await bench.dictate()
        bench.coordinator.escape()
        XCTAssertEqual(bench.media.reads, 0)
        XCTAssertEqual(bench.media.commands, [])
    }

    /// A press that only asks for the microphone listens to nothing, so it
    /// has no business pausing anything.
    func testNothingIsReadWhileAskingForTheMicrophone() async {
        let bench = Bench(microphoneGranted: false)
        bench.coordinator.keyDown(language: .frFR)
        await bench.coordinator.permission?.value
        XCTAssertEqual(bench.media.reads, 0)
        XCTAssertEqual(bench.media.commands, [])
    }

    /// The engine is started in the session's language, which is the
    /// shortcut's: that's the whole point of the second one.
    func testTheEngineListensInTheLanguageOfThePress() async {
        let bench = Bench()
        bench.coordinator.keyDown(language: .enUS)
        await bench.settle { bench.engine.starts == 1 }
        XCTAssertEqual(bench.engine.startedLocales.map(\.identifier), ["en-US"])
    }

    /// Raw and cleaned both enter the history, even though only the cleaned
    /// one was pasted: the transcript is the one thing a bad cleanup can't
    /// take away.
    func testTheHistoryKeepsTheRawNextToTheCleanedText() async {
        let bench = Bench()
        await bench.dictate()
        let entry = bench.history.recents.entries.first
        XCTAssertEqual(entry?.raw, "bonjour")
        XCTAssertEqual(entry?.cleaned, "Bonjour.")
        XCTAssertEqual(entry?.language, DictationLanguage.frFR.rawValue)
    }

    // MARK: - The vocabulary

    /// Recognition leans towards the speaker's own words from the first one
    /// said: the terms go to the engine along with the language.
    func testTheEngineIsStartedWithTheVocabularyTerms() async {
        let bench = Bench(vocabulary: "Okonoma\nl'a pas compris → Lapacompris")
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.engine.starts == 1 }
        XCTAssertEqual(bench.engine.startedContextualStrings, [["Okonoma", "Lapacompris"]])
    }

    /// No vocabulary, no difference: the engine is asked for nothing more,
    /// the model gets the transcript as heard and the prompt as it was.
    func testWithoutAVocabularyNothingChanges() async {
        let bench = Bench()
        await bench.dictate()
        XCTAssertEqual(bench.engine.startedContextualStrings, [[]])
        XCTAssertEqual(bench.client.texts, ["bonjour"])
        XCTAssertEqual(bench.client.systems, [DictationCleanup.systemPrompt])
    }

    /// The replacements come before anything else reads the text: the model
    /// cleans up the transcript as the speaker spells it, and that is the
    /// raw text the history keeps.
    func testReplacementsReachTheModelAndTheHistory() async {
        let bench = Bench(events: [.partial("ouvre l'a"), .final("ouvre l'a pas compris")],
                          vocabulary: "l'a pas compris → Lapacompris")
        await bench.dictate()
        XCTAssertEqual(bench.client.texts, ["ouvre Lapacompris"])
        XCTAssertEqual(bench.history.recents.entries.first?.raw, "ouvre Lapacompris")
    }

    /// Raw has no model to fix anything: the replacements are all it gets,
    /// and what it pastes.
    func testRawPastesTheTranscriptWithItsReplacements() async {
        let bench = Bench(events: [.final("ouvre l'a pas compris")],
                          model: .raw,
                          vocabulary: "l'a pas compris → Lapacompris")
        await bench.dictate()
        XCTAssertEqual(bench.pasted, ["ouvre Lapacompris"])
        XCTAssertEqual(bench.history.recents.entries.first?.raw, "ouvre Lapacompris")
    }

    /// The model is told which spellings to keep, after the prompt it gets
    /// anyway.
    func testTheCleanupPromptNamesTheTerms() async {
        let bench = Bench(vocabulary: "Okonoma\nl'a pas compris → Lapacompris")
        await bench.dictate()
        XCTAssertEqual(bench.client.systems,
                       [DictationCleanup.systemPrompt(keeping: ["Okonoma", "Lapacompris"])])
        let sent = bench.client.systems.first ?? ""
        XCTAssertTrue(sent.hasPrefix(DictationCleanup.systemPrompt), sent)
        XCTAssertTrue(sent.contains("Okonoma") && sent.contains("Lapacompris"), sent)
        // The heard side is a mistake to fix, not a spelling to keep.
        XCTAssertFalse(sent.contains("l'a pas compris"), sent)
    }

    /// Read once, on the press, like the language and the model: edited
    /// mid-dictation, the vocabulary waits for the next one, so the engine,
    /// the replacements and the prompt never disagree.
    func testTheVocabularyIsTheOneOfThePress() async {
        let bench = Bench(events: [.final("ouvre l'a pas compris")],
                          model: .raw,
                          vocabulary: "l'a pas compris → Lapacompris")
        bench.coordinator.keyDown(language: .frFR)
        bench.vocabulary = .empty
        await bench.finish()
        XCTAssertEqual(bench.pasted, ["ouvre Lapacompris"])
    }

    // MARK: - What the dictation becomes

    /// The shortcut's output decides what the one call is asked for: speak
    /// French, paste corrected English, in a single pass over the transcript.
    func testTheOutputOfThePressComposesTheOnlyCall() async {
        let bench = Bench(answer: .success("Hello."))
        await bench.dictate(output: .translateEN)

        XCTAssertEqual(bench.client.calls, 1)
        XCTAssertEqual(bench.client.systems, [DictationOutput.translateEN.systemPrompt(keeping: [])])
        XCTAssertEqual(bench.client.texts, ["bonjour"])
        XCTAssertEqual(bench.pasted, ["Hello."])
    }

    /// The vocabulary survives the composition: the spellings to keep are
    /// still named, after the output's own instruction.
    func testTheVocabularyStillReachesAComposedPrompt() async {
        let bench = Bench(vocabulary: "Okonoma")
        await bench.dictate(output: .makePrompt)
        XCTAssertEqual(bench.client.systems,
                       [DictationOutput.makePrompt.systemPrompt(keeping: ["Okonoma"])])
    }

    /// A rough idea turned into a prompt runs longer than what was said:
    /// the call gets the room, where the cleanup's budget would cut it off.
    func testAPromptOutputAsksForMoreRoomThanACleanup() async {
        let bench = Bench()
        await bench.dictate(output: .makePrompt)

        XCTAssertEqual(bench.client.budgets, [DictationOutput.makePrompt.maxTokens(forRawLength: 7)])
        XCTAssertGreaterThan(bench.client.budgets.first ?? 0,
                             DictationCleanup.maxTokens(forRawLength: 7))
    }

    /// Nothing chosen is the cleanup: byte for byte the prompt and budget
    /// of before there was an output at all.
    func testTheDefaultOutputChangesNothing() async {
        let bench = Bench()
        await bench.dictate()

        XCTAssertEqual(bench.client.systems, [DictationCleanup.systemPrompt])
        XCTAssertEqual(bench.client.budgets, [DictationCleanup.maxTokens(forRawLength: 7)])
    }

    /// The panel says which of the three is running, so the session carries
    /// the output the press chose — not the one Settings holds now.
    func testTheSessionCarriesTheOutputOfThePress() async throws {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR, output: .translateEN)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.settle { bench.engine.starts == 1 }

        XCTAssertEqual(session.output, .translateEN)
    }

    /// "Raw" names no model: there is no call for an output to shape, and
    /// the transcript is pasted as it was heard.
    func testRawPastesAsHeardWhateverTheOutput() async {
        let bench = Bench(model: .raw)
        await bench.dictate(output: .makePrompt)

        XCTAssertEqual(bench.client.calls, 0)
        XCTAssertEqual(bench.pasted, ["bonjour"])
    }

    // MARK: - Where the dictation is going

    /// A Slack message, an email and a prompt typed into a terminal are not
    /// written the same way. The app that had focus when the key went down is
    /// where the text will land, and the model is told its name — the name
    /// alone, and it takes it from there.
    func testTheModelIsToldWhichAppTheTextIsGoingInto() async {
        let bench = Bench()
        bench.targetAppName = "Slack"
        await bench.dictate()

        XCTAssertEqual(bench.client.systems,
                       [DictationCleanup.systemPrompt(keeping: [], pastedInto: "Slack")])
        XCTAssertEqual(bench.pasted, ["Bonjour."])
    }

    /// Whatever the shortcut turns the dictation into, it still lands in an
    /// app: a translation is told where it is going too, and the spellings to
    /// keep survive next to it.
    func testAComposedOutputIsToldWhereTheTextIsGoingToo() async {
        let bench = Bench(vocabulary: "Okonoma", answer: .success("Hello."))
        bench.targetAppName = "Mail"
        await bench.dictate(output: .translateEN)

        XCTAssertEqual(bench.client.systems,
                       [DictationOutput.translateEN.systemPrompt(keeping: ["Okonoma"],
                                                                 pastedInto: "Mail")])
    }

    /// "Raw" asks no model anything, so there is nothing to tell: the
    /// transcript is pasted as it was heard, app or no app.
    func testRawIsToldNothingBecauseItAsksNoModel() async {
        let bench = Bench(model: .raw)
        bench.targetAppName = "Terminal"
        await bench.dictate()

        XCTAssertEqual(bench.client.calls, 0)
        XCTAssertEqual(bench.pasted, ["bonjour"])
    }

    // MARK: - Hands-free: a tap locks the microphone open

    /// Under 300 ms the key was tapped, not held. Holding a key through a
    /// long dictation is the hard part, so a tap no longer drops anything:
    /// the microphone stays open, the words keep coming with the key up, and
    /// nothing is closed or pasted until the dictation is told to finish.
    func testATapLocksListeningInsteadOfCancelling() async throws {
        let bench = Bench()
        let session = try await bench.lock()
        bench.engine.say(.partial("bonjour tout le monde"))
        await bench.settle { session.transcript == "bonjour tout le monde" }

        XCTAssertTrue(session.isLocked)
        XCTAssertEqual(session.phase, .listening)
        XCTAssertEqual(session.transcript, "bonjour tout le monde")
        XCTAssertEqual(bench.engine.stops, 0)
        XCTAssertEqual(bench.engine.cancels, 0)
        XCTAssertTrue(bench.pasted.isEmpty)
        XCTAssertTrue(bench.coordinator.session === session)
    }

    /// A hold is what it always was: released past the threshold, it closes
    /// the microphone on the spot and never locks.
    func testAHoldFinishesOnReleaseAndNeverLocks() async throws {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.settle { bench.engine.starts == 1 }

        bench.hold(for: 0.35)
        bench.coordinator.keyUp()
        XCTAssertFalse(session.isLocked)
        XCTAssertEqual(session.phase, .finishing)
        XCTAssertEqual(bench.engine.stops, 1)

        await bench.cycleEnds()
        XCTAssertEqual(bench.pasted, ["Bonjour."])
    }

    /// The press after a tap is the release a hold would have had: the
    /// microphone closes, the music resumes behind it, and the cleaned-up
    /// text is pasted — the same way out as a hold, phase for phase.
    func testTheNextPressFinishesALockedDictationAndPastes() async throws {
        let bench = Bench()
        let session = try await bench.lock()
        let log = bench.watch(session)

        bench.coordinator.keyDown(language: .frFR)
        XCTAssertEqual(bench.engine.stops, 1)
        XCTAssertEqual(bench.engine.cancels, 0)
        XCTAssertEqual(bench.media.commands, [.pause, .play])
        XCTAssertEqual(bench.media.microphoneClosesAtResume, [1])
        await bench.cycleEnds()

        XCTAssertEqual(log.phases, [.listening, .finishing, .cleaning, .pasting])
        XCTAssertEqual(bench.pasted, ["Bonjour."])
        XCTAssertEqual(bench.engine.starts, 1)
        XCTAssertNil(bench.coordinator.session)
        // The release of that press, the paste and the panel closing: still
        // the one resume.
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// Either shortcut ends a locked dictation. The other one's press
    /// finishes it in the language it was started in, rather than starting
    /// over in its own.
    func testEitherShortcutFinishesALockedDictation() async throws {
        let bench = Bench()
        try await bench.lock(language: .frFR)

        bench.coordinator.keyDown(language: .enUS)
        await bench.cycleEnds()

        XCTAssertEqual(bench.engine.startedLocales.map(\.identifier), ["fr-FR"])
        XCTAssertEqual(bench.pasted, ["Bonjour."])
    }

    /// The press that finishes still has a release to come, and a quick
    /// one: it must read as neither a slip that cancels nor a tap that locks
    /// again. The dictation carries on to its paste.
    func testTheReleaseOfTheFinishingPressDoesNothing() async throws {
        let bench = Bench()
        let session = try await bench.lock()

        bench.coordinator.keyDown(language: .frFR)
        bench.hold(for: 0.1)
        bench.coordinator.keyUp()

        XCTAssertEqual(session.phase, .finishing)
        XCTAssertTrue(bench.coordinator.session === session)
        XCTAssertEqual(bench.engine.stops, 1)
        XCTAssertEqual(bench.engine.cancels, 0)
        await bench.cycleEnds()
        XCTAssertEqual(bench.pasted, ["Bonjour."])
        XCTAssertEqual(bench.engine.starts, 1)
    }

    /// Esc on a locked dictation is Esc as ever: the microphone cancelled,
    /// nothing pasted or remembered, and the music back.
    func testEscapeCancelsALockedDictationAndResumesTheMusic() async throws {
        let bench = Bench()
        let session = try await bench.lock()
        XCTAssertTrue(session.isLocked)
        XCTAssertEqual(bench.media.commands, [.pause])

        bench.coordinator.escape()

        XCTAssertEqual(bench.engine.cancels, 1)
        XCTAssertEqual(bench.engine.stops, 0)
        XCTAssertTrue(bench.pasted.isEmpty)
        XCTAssertTrue(bench.history.recents.entries.isEmpty)
        XCTAssertNil(bench.coordinator.session)
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// A tap nobody follows up doesn't listen forever: past the limit, the
    /// dictation finishes as if pressed again — pasted, not dropped — and the
    /// music resumes with it.
    func testALockedDictationFinishesByItselfAtItsLimit() async throws {
        let bench = Bench(lockedLimit: .milliseconds(5))
        try await bench.lock()

        await bench.wait { bench.engine.stops == 1 }
        await bench.cycleEnds()

        XCTAssertEqual(bench.pasted, ["Bonjour."])
        XCTAssertEqual(bench.media.commands, [.pause, .play])
        XCTAssertEqual(bench.media.microphoneClosesAtResume, [1])
    }

    /// The limit belongs to the dictation that locked. Once that one has
    /// ended, it must not reach into the next and stop it mid-sentence.
    func testTheLimitOfAnEndedLockedDictationSparesTheNextOne() async throws {
        let bench = Bench(lockedLimit: .milliseconds(20))
        try await bench.lock()
        bench.coordinator.escape()

        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.engine.starts == 2 }
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(bench.engine.stops, 0)
        XCTAssertEqual(bench.coordinator.session?.phase, .listening)
    }

    /// A locked dictation can end on a silence too: the panel says so, as
    /// for a held one, and the music doesn't wait for it to close.
    func testNothingHeardOnALockedDictationPastesNothing() async throws {
        let bench = Bench(events: [.partial("  "), .final("   ")])
        let session = try await bench.lock()

        bench.coordinator.keyDown(language: .frFR)
        await bench.cycleEnds()

        XCTAssertEqual(session.phase, .empty)
        XCTAssertTrue(bench.pasted.isEmpty)
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// The engine giving up minutes into a locked dictation shows why, and
    /// resumes the music at once.
    func testAFailureWhileLockedResumesTheMusic() async throws {
        let bench = Bench()
        let session = try await bench.lock()

        bench.engine.say(.failed(.recognizer("timeout")))
        await bench.cycleEnds()

        XCTAssertEqual(session.phase,
                       .error(SpeechEngineError.recognizer("timeout").localizedDescription))
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// Minutes of listening leave the engine time to end a locked dictation
    /// before any press does. Its microphone is closed then, so the music
    /// resumes — even when the text has nowhere to go and the panel stays up
    /// with it.
    func testWhenTheEngineEndsALockedDictationTheMusicResumes() async throws {
        let bench = Bench()
        bench.targetApp = nil
        let session = try await bench.lock()

        bench.engine.say(.final("bonjour"))
        await bench.cycleEnds()

        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    // MARK: - Presses that paste nothing

    /// Esc at any phase: the microphone is cancelled, the cycle is dropped,
    /// nothing is pasted. The clipboard is untouched because the only path
    /// that writes it is the paste, which never ran.
    func testEscapeCancelsWithoutPasting() async {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.engine.starts == 1 }

        bench.coordinator.escape()

        XCTAssertEqual(bench.engine.cancels, 1)
        XCTAssertTrue(bench.pasted.isEmpty)
        XCTAssertTrue(bench.history.recents.entries.isEmpty)
        XCTAssertNil(bench.coordinator.session)
    }

    /// A silence: the panel says it heard nothing rather than pasting an
    /// empty string, and no model is asked to clean up nothing.
    func testNothingHeardPastesNothing() async throws {
        let bench = Bench(events: [.partial("  "), .final("   ")])
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.settle { bench.engine.starts == 1 }

        bench.hold(for: 1)
        bench.coordinator.keyUp()
        await bench.coordinator.cycle?.value

        XCTAssertEqual(session.phase, .empty)
        XCTAssertTrue(bench.pasted.isEmpty)
        XCTAssertTrue(bench.clientRequests.isEmpty)
        XCTAssertTrue(bench.history.recents.entries.isEmpty)
    }

    /// The engine gives up (no microphone, language not installed): its own
    /// message is shown, and the panel stays on it — long enough to be read.
    func testAnEngineFailureShowsItsMessage() async throws {
        let bench = Bench(events: [.failed(.microphoneDenied)])
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.coordinator.cycle?.value

        XCTAssertEqual(session.phase,
                       .error(SpeechEngineError.microphoneDenied.localizedDescription))
        XCTAssertTrue(bench.pasted.isEmpty)
        XCTAssertNotNil(bench.coordinator.session)
    }

    /// A failure isn't a panel that stays forever: the message is shown, then
    /// the panel takes itself off the screen, as "Nothing heard" does. Before
    /// that it was Esc or nothing, and `keyUp()` doesn't answer in that phase.
    func testAFailureClosesThePanelOnItsOwn() async {
        let bench = Bench(events: [.failed(.microphoneDenied)],
                          durations: .init(empty: .milliseconds(5), failure: .milliseconds(5)))
        bench.coordinator.keyDown(language: .frFR)
        await bench.coordinator.cycle?.value
        XCTAssertNotNil(bench.coordinator.session)

        await bench.wait { bench.coordinator.session == nil }
        XCTAssertNil(bench.coordinator.session)
    }

    /// The panel is handed the error itself, not only its sentence: a missing
    /// language is the one failure it can offer a way out of, and offering it
    /// takes knowing which failure it was.
    func testAFailureKeepsTheErrorItselfNotJustItsMessage() async throws {
        let missing = SpeechEngineError.languageUnavailable(DictationLanguage.frFR.locale)
        let bench = Bench(events: [.failed(missing)])
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.coordinator.cycle?.value

        XCTAssertEqual(session.phase, .error(missing.localizedDescription))
        guard case .languageUnavailable? = session.failure else {
            return XCTFail("no way out without the error: \(String(describing: session.failure))")
        }
        XCTAssertNotNil(session.failure?.settingsURL)
    }

    // MARK: - Permissions

    /// Without the microphone and speech recognition, the press asks for
    /// them and explains itself — it doesn't listen. No panel opens, the
    /// engine is never started, and the next press is the one that dictates.
    func testARefusedMicrophoneListensToNothing() async {
        let bench = Bench(microphoneGranted: false)
        bench.coordinator.keyDown(language: .frFR)
        await bench.coordinator.permission?.value

        XCTAssertEqual(bench.permissionRequests, 1)
        XCTAssertEqual(bench.explanations, 1)
        XCTAssertEqual(bench.engine.starts, 0)
        XCTAssertEqual(bench.panels, 0)
        XCTAssertNil(bench.coordinator.session)
    }

    /// Pressed again while the system prompts are still up: the first chain
    /// is dropped, so a single explanation is shown. Two stacked alerts is
    /// what a shortcut pressed twice would otherwise cost, on the very
    /// machine where nothing works yet.
    func testASecondPressDoesNotStackTwoExplanations() async {
        let bench = Bench(microphoneGranted: false, promptsWait: true)
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.permissionRequests == 1 }
        let first = bench.coordinator.permission

        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.permissionRequests == 2 }
        bench.answerPrompts(granted: false)
        await first?.value
        await bench.coordinator.permission?.value

        XCTAssertEqual(first?.isCancelled, true)
        XCTAssertEqual(bench.explanations, 1)
    }

    /// A permission already granted costs nothing: no prompt, no
    /// explanation, and the microphone opens on the press itself.
    func testAGrantedMicrophoneAsksForNothing() async {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR)
        await bench.settle { bench.engine.starts == 1 }

        XCTAssertEqual(bench.permissionRequests, 0)
        XCTAssertEqual(bench.explanations, 0)
        XCTAssertNil(bench.coordinator.permission)
    }

    // MARK: - The cleanup, and what happens without it

    /// "Raw" names no model: the transcript is pasted as it was heard and
    /// nothing is ever asked of a client.
    func testRawPastesTheTranscriptWithoutAskingAModel() async {
        let bench = Bench(model: .raw)
        await bench.dictate()

        XCTAssertTrue(bench.clientRequests.isEmpty)
        XCTAssertEqual(bench.client.calls, 0)
        XCTAssertEqual(bench.pasted, ["bonjour"])
        // Nothing cleaned it up, so the history holds the transcript alone.
        XCTAssertNil(bench.history.recents.entries.first?.cleaned)
    }

    /// A dictation is never lost: the model failing costs the cleanup, not
    /// the text. The transcript is pasted and the panel says why.
    func testAFailedCleanupPastesTheTranscriptWithANote() async throws {
        let bench = Bench(answer: .failure(CleanupFailure()))
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.finish()

        XCTAssertEqual(bench.pasted, ["bonjour"])
        XCTAssertEqual(session.note,
                       loc("Collé sans nettoyage : Ollama ne répond pas",
                           en: "Pasted without cleanup: Ollama isn’t answering"))
        XCTAssertNil(bench.history.recents.entries.first?.cleaned)
    }

    /// No client at all (a Claude model with no key in the Keychain): same
    /// outcome, the reason changes.
    func testAMissingKeyPastesTheTranscriptWithANote() async throws {
        let bench = Bench(hasClient: false)
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.finish()

        XCTAssertEqual(bench.clientRequests, [.claude(.haiku45)])
        XCTAssertEqual(bench.pasted, ["bonjour"])
        XCTAssertEqual(session.note,
                       loc("Collé sans nettoyage : clé API manquante",
                           en: "Pasted without cleanup: no API key"))
    }

    // MARK: - The panel

    /// Nowhere to paste: Claudio itself was frontmost when the key went down
    /// — the cursor in its own prompt editor, say. Nothing is pasted at all,
    /// because a ⌘V would land in whatever has focus now, Claudio included.
    /// The panel stays open with the text, which Copy can still save, and the
    /// history has it either way.
    func testAPasteWithNowhereToGoIsNotSentAnyway() async throws {
        let bench = Bench()
        bench.targetApp = nil
        bench.coordinator.keyDown(language: .frFR)
        let session = try XCTUnwrap(bench.coordinator.session)
        await bench.finish()

        XCTAssertTrue(bench.pasted.isEmpty)
        XCTAssertEqual(session.phase, .done)
        XCTAssertTrue(session.canCopy)
        XCTAssertNotNil(bench.coordinator.session)
        XCTAssertEqual(bench.history.recents.entries.count, 1)
    }

    /// The panel leaves the screen before the keystroke, as the correction
    /// panel does and for the same reason: it is a key window while it is up,
    /// and a ⌘V sent to it pastes the dictation into Claudio. Read through
    /// the session, which `dismiss()` clears: it is already gone when the
    /// paste runs.
    func testThePanelIsGoneBeforeTheKeystroke() async {
        let bench = Bench()
        await bench.dictate()

        XCTAssertEqual(bench.pasted, ["Bonjour."])
        XCTAssertEqual(bench.panelOpenAtPaste, [false])
    }

    /// A shortcut pressed while a dictation is running starts a fresh one:
    /// the first microphone is cancelled and its session dropped.
    func testANewPressRestartsTheCycle() async throws {
        let bench = Bench()
        bench.coordinator.keyDown(language: .frFR)
        let first = try XCTUnwrap(bench.coordinator.session)
        await bench.settle { bench.engine.starts == 1 }

        bench.coordinator.keyDown(language: .enUS)
        let second = try XCTUnwrap(bench.coordinator.session)
        await bench.settle { bench.engine.starts == 2 }

        XCTAssertFalse(first === second)
        XCTAssertEqual(bench.engine.cancels, 1)
        XCTAssertEqual(bench.engine.startedLocales.map(\.identifier), ["fr-FR", "en-US"])
        XCTAssertTrue(bench.pasted.isEmpty)
    }
}

// MARK: - The bench

/// One coordinator and the fakes it was built with, plus what a test needs
/// to drive it: a clock it moves by hand, and the texts the paste received.
@MainActor
private final class Bench {
    let engine: FakeSpeechEngine
    let client: FakeStreamClient
    let history: DictationHistory
    /// Built in `init` and never cleared: the tests see it as what it is.
    var coordinator: DictationCoordinator { built }
    private var built: DictationCoordinator!

    /// Every text the paste was handed, in order.
    var pasted: [String] = []
    /// Whether a dictation was still on screen each time the paste ran: the
    /// panel has to be gone before the keystroke.
    var panelOpenAtPaste: [Bool] = []
    /// The app that had focus when the key went down, `nil` when Claudio
    /// itself did and there is nowhere to paste.
    var targetApp: NSRunningApplication? = .current
    /// That app's name, as the cleanup will be told it. `nil` by default —
    /// an app macOS names nothing — so every other test here reads the prompt
    /// of before there was a destination.
    var targetAppName: String?
    /// Every model a client was asked for: empty proves nothing was asked.
    var clientRequests: [ModelChoice] = []
    /// What the settings hold right now. Changing it mid-dictation is how a
    /// test proves the press already read it.
    var vocabulary: DictationVocabulary
    /// Whether the microphone and speech recognition are already granted.
    let microphoneGranted: Bool
    /// How many times the system prompts were asked for, and how many times
    /// the explanation replaced them.
    var permissionRequests = 0
    var explanations = 0
    /// How many panels were put on screen: nothing is heard without one.
    var panels = 0
    /// What plays on the Mac, and the pauser the coordinator tells about
    /// each listening: the commands land in the first, the read under way is
    /// the second's.
    let media: FakeMediaPlayback
    let pauser: MediaPauser

    private var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// The prompts still waiting for an answer, when the bench holds them
    /// open: that's a press landing while macOS asks for the microphone.
    private var pendingPrompts: [CheckedContinuation<Bool, Never>] = []

    init(events: [TranscriptEvent] = [.partial("bon"), .partial("bonjour"), .final("bonjour")],
         model: ModelChoice = .claude(.haiku45),
         vocabulary: String = "",
         answer: Result<String, Error> = .success("Bonjour."),
         hasClient: Bool = true,
         microphoneGranted: Bool = true,
         promptsWait: Bool = false,
         playing: Bool = true,
         readsWait: Bool = false,
         pausesMedia: Bool = true,
         durations: DictationCoordinator.MessageDurations = .standard,
         lockedLimit: Duration = DictationCoordinator.longestLockedDictation) {
        self.microphoneGranted = microphoneGranted
        self.vocabulary = DictationVocabulary(parsing: vocabulary)
        let engine = FakeSpeechEngine(events)
        self.engine = engine
        client = FakeStreamClient(answer)
        let media = FakeMediaPlayback(playing: playing, readsWait: readsWait)
        media.microphoneCloses = { engine.stops + engine.cancels }
        self.media = media
        pauser = MediaPauser(playback: media.playback)
        history = DictationHistory(
            defaults: UserDefaults(suiteName: "ClaudioTests.dictation.\(UUID().uuidString)")!
        )
        let client = self.client
        built = DictationCoordinator(
            engine: engine,
            model: { model },
            vocabulary: { [weak self] in self?.vocabulary ?? .empty },
            client: { [weak self] choice in
                self?.clientRequests.append(choice)
                return hasClient ? client : nil
            },
            pasting: PasteService(
                isAllowed: { true },
                capture: { [weak self] in
                    PasteTarget(app: self?.targetApp, clipboard: nil, appName: self?.targetAppName)
                },
                paste: { [weak self] text, _ in
                    guard let self else { return false }
                    pasted.append(text)
                    panelOpenAtPaste.append(coordinator.session != nil)
                    return targetApp != nil
                }
            ),
            microphone: MicrophoneGate(
                isGranted: { [weak self] in self?.microphoneGranted ?? false },
                request: { [weak self] in
                    guard let self else { return false }
                    permissionRequests += 1
                    guard promptsWait else { return microphoneGranted }
                    return await withCheckedContinuation { pendingPrompts.append($0) }
                },
                showExplanation: { [weak self] in self?.explanations += 1 }
            ),
            panel: { [weak self] _, _ in
                self?.panels += 1
                return nil
            },
            history: history,
            pauser: pauser,
            pausesMedia: { pausesMedia },
            durations: durations,
            lockedLimit: lockedLimit,
            now: { [weak self] in self?.clock ?? .distantPast }
        )
    }

    /// Answers every system prompt still open, as macOS does when the user
    /// finally clicks.
    func answerPrompts(granted: Bool) {
        let waiting = pendingPrompts
        pendingPrompts = []
        for prompt in waiting { prompt.resume(returning: granted) }
    }

    /// Moves the clock forward: that's how long the key stayed down.
    func hold(for seconds: TimeInterval) { clock += seconds }

    /// A full dictation: press, speak, release, and wait for the text to land.
    func dictate(language: DictationLanguage = .frFR,
                 output: DictationOutput = .cleanup) async {
        coordinator.keyDown(language: language, output: output)
        await finish()
    }

    /// A tap: the key down, the engine started, and the key up again before
    /// the threshold. Hands back the dictation it locked.
    @discardableResult
    func lock(language: DictationLanguage = .frFR) async throws -> DictationSession {
        let starts = engine.starts
        coordinator.keyDown(language: language)
        let session = try XCTUnwrap(coordinator.session)
        await settle { engine.starts == starts + 1 }
        await readAnswered()
        hold(for: 0.1)
        coordinator.keyUp()
        return session
    }

    /// Waits for the cycle under way to end. One that never does — a
    /// dictation nothing finishes, the stream still open — fails its test
    /// instead of hanging the suite: past the ceiling it is cancelled.
    func cycleEnds(seconds: TimeInterval = 2,
                   file: StaticString = #filePath, line: UInt = #line) async {
        guard let cycle = coordinator.cycle else { return }
        let ceiling = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            XCTFail("the dictation never finished", file: file, line: line)
            cycle.cancel()
        }
        await cycle.value
        ceiling.cancel()
    }

    /// Releases a press already under way and waits for the cycle to end.
    func finish() async {
        await settle { engine.starts == 1 }
        await readAnswered()
        hold(for: 1)
        coordinator.keyUp()
        await coordinator.cycle?.value
    }

    /// Lets the press's read answer, as it does within a real hold — unless
    /// the test answers it by hand.
    func readAnswered() async {
        guard !media.readsWait else { return }
        await pauser.read?.value
    }

    /// Lets the coordinator's task run. Everything here is on the main actor
    /// and nothing waits on the outside world, so a few turns are enough;
    /// the ceiling only keeps a broken cycle from hanging the suite.
    func settle(until reached: () -> Bool) async {
        var turns = 0
        while !reached(), turns < 500 {
            await Task.yield()
            turns += 1
        }
    }

    /// Waits for something a timer decides rather than a turn of the loop: a
    /// panel closing itself is the only thing here that takes real time. The
    /// ceiling keeps a panel that never closes from hanging the suite.
    func wait(seconds: TimeInterval = 2, until reached: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !reached(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Records every phase the session goes through, in order.
    func watch(_ session: DictationSession) -> PhaseLog {
        let log = PhaseLog()
        log.subscription = session.$phase.sink { log.phases.append($0) }
        return log
    }
}

private final class PhaseLog {
    var phases: [DictationSession.Phase] = []
    var subscription: AnyCancellable?
}

/// Replays a fixed list of events. The partials go out as soon as the engine
/// starts, as a real one does while the key is held; the final waits for
/// `stop()`, since it's the microphone closing that ends a session. A
/// failure doesn't wait for anything.
///
/// `@unchecked Sendable`: everything it does happens on the main actor.
private final class FakeSpeechEngine: SpeechEngine, @unchecked Sendable {
    private let events: [TranscriptEvent]
    private var continuation: AsyncStream<TranscriptEvent>.Continuation?

    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancels = 0
    private(set) var startedLocales: [Locale] = []
    /// The terms each start was biased towards, one list per start.
    private(set) var startedContextualStrings: [[String]] = []

    init(_ events: [TranscriptEvent]) { self.events = events }

    func start(locale: Locale, contextualStrings: [String]) -> AsyncStream<TranscriptEvent> {
        starts += 1
        startedLocales.append(locale)
        startedContextualStrings.append(contextualStrings)
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
        self.continuation = continuation
        for event in events {
            switch event {
            case .partial, .level:
                continuation.yield(event)
            case .failed:
                continuation.yield(event)
                continuation.finish()
            case .final:
                break
            }
        }
        return stream
    }

    /// What the engine says later on, while the dictation goes on: another
    /// partial, or an end it reaches by itself — a final, a failure.
    func say(_ event: TranscriptEvent) {
        continuation?.yield(event)
        switch event {
        case .final, .failed: continuation?.finish()
        case .partial, .level: break
        }
    }

    func stop() {
        stops += 1
        for case .final(let text) in events {
            continuation?.yield(.final(text))
        }
        continuation?.finish()
    }

    func cancel() {
        cancels += 1
        continuation?.finish()
    }
}

/// Answers a fixed text in two pieces, or throws. Counts its calls, so a
/// test can prove "Raw" never asks a model anything, and keeps what each
/// call was sent: the text to clean up, the prompt it came with, and the
/// room its answer was given.
private final class FakeStreamClient: TextStreamClient, @unchecked Sendable {
    private let answer: Result<String, Error>
    private(set) var calls = 0
    private(set) var texts: [String] = []
    private(set) var systems: [String] = []
    private(set) var budgets: [Int] = []

    init(_ answer: Result<String, Error>) { self.answer = answer }

    func streamCompletion(of text: String,
                          system: String,
                          maxTokens: Int,
                          onDelta: @escaping @Sendable (String) async -> Void) async throws -> StreamResult {
        calls += 1
        texts.append(text)
        systems.append(system)
        budgets.append(maxTokens)
        let cleaned = try answer.get()
        let middle = cleaned.index(cleaned.startIndex, offsetBy: cleaned.count / 2)
        await onDelta(String(cleaned[..<middle]))
        await onDelta(String(cleaned[middle...]))
        return StreamResult(text: cleaned, truncated: false, inputTokens: 0, outputTokens: 0)
    }
}

/// What a model that isn't answering looks like from here.
private struct CleanupFailure: LocalizedError {
    var errorDescription: String? {
        loc("Ollama ne répond pas", en: "Ollama isn’t answering")
    }
}
