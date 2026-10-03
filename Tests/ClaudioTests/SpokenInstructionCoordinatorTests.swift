import AppKit
import XCTest
@testable import Claudio

/// Saying the instruction instead of typing it: the free action's shortcut,
/// held. From the key going down to the transform starting, with no
/// microphone, no screen and no selection — the engine replays a fixed list
/// of events, the panel is four closures that remember what they were asked,
/// and the clock is moved by hand.
@MainActor
final class SpokenInstructionCoordinatorTests: XCTestCase {

    // MARK: - The two gestures

    /// Held: the microphone opens on the press, the words arrive while the
    /// key is down, and the release hands the instruction to the free
    /// action. Nothing is asked of a model: an instruction is read, not
    /// pasted.
    func testAHoldSpeaksTheInstructionThenRunsIt() async {
        let bench = Bench()
        bench.coordinator.keyDown()
        await bench.settle { bench.engine.starts == 1 }
        XCTAssertEqual(bench.listens, 1)
        XCTAssertEqual(bench.session.phase, .listeningInstruction)

        bench.hold(for: 1)
        bench.coordinator.keyUp()
        XCTAssertEqual(bench.engine.stops, 1)
        // The microphone is shut while the engine has its last word: the
        // panel stops claiming to be listening.
        XCTAssertTrue(bench.session.listeningEnded)
        await bench.cycleEnds()

        XCTAssertEqual(bench.ran, ["traduis en espagnol"])
        XCTAssertEqual(bench.session.instruction, "traduis en espagnol")
        XCTAssertEqual(bench.typed, 0)
        XCTAssertEqual(bench.closed, 0)
    }

    /// Tapped, it is the field where the instruction is typed — today's
    /// behaviour, in the panel the press already opened over the same
    /// selection: nothing is captured twice. The word caught on the way is
    /// dropped, since it was never meant to be the instruction.
    func testATapGivesBackTheFieldWhereTheInstructionIsTyped() async {
        let bench = Bench()
        bench.coordinator.keyDown()
        await bench.settle { bench.session.instruction == "traduis en espagnol" }

        bench.hold(for: 0.1)
        bench.coordinator.keyUp()

        XCTAssertEqual(bench.session.phase, .askingInstruction)
        XCTAssertEqual(bench.session.instruction, "")
        XCTAssertEqual(bench.engine.cancels, 1)
        XCTAssertEqual(bench.engine.stops, 0)
        XCTAssertTrue(bench.ran.isEmpty)
        XCTAssertEqual(bench.listens, 1)
        XCTAssertEqual(bench.typed, 0)
        XCTAssertFalse(bench.media.leftPaused)
    }

    /// The words show up as they are said, in the very field they would have
    /// been typed in.
    func testTheWordsShowUpAsTheyAreSaid() async {
        let bench = Bench(events: [.partial("mets"), .partial("mets en gras")])
        bench.coordinator.keyDown()
        await bench.settle { bench.session.instruction == "mets en gras" }
        XCTAssertEqual(bench.session.phase, .listeningInstruction)
    }

    /// The microphone's loudness goes to the waveform, newest last, and
    /// leaves the instruction alone.
    func testTheMicrophonesLoudnessFeedsTheWaveform() async {
        let bench = Bench(events: [.level(0.25), .partial("mets"), .level(0.75)])
        bench.coordinator.keyDown()
        await bench.settle { bench.session.levels.values.last == 0.75 }
        XCTAssertEqual(Array(bench.session.levels.values.suffix(2)), [0.25, 0.75])
        XCTAssertEqual(bench.session.instruction, "mets")
    }

    /// A shortcut pressed again while it listens starts over: the first
    /// microphone is dropped and a fresh panel opens on the selection.
    func testANewPressStartsAFreshListening() async {
        let bench = Bench()
        bench.coordinator.keyDown()
        await bench.settle { bench.engine.starts == 1 }

        bench.coordinator.keyDown()
        await bench.settle { bench.engine.starts == 2 }

        XCTAssertEqual(bench.engine.cancels, 1)
        XCTAssertEqual(bench.listens, 2)
        XCTAssertTrue(bench.ran.isEmpty)
    }

    // MARK: - The vocabulary

    /// Recognition leans towards the speaker's own words, exactly as it does
    /// in a dictation: the terms go to the engine along with the language.
    func testTheEngineIsStartedWithTheVocabularyTerms() async {
        let bench = Bench(vocabulary: "Okonoma\nl'a pas compris → Lapacompris")
        bench.coordinator.keyDown()
        await bench.settle { bench.engine.starts == 1 }

        XCTAssertEqual(bench.engine.startedContextualStrings, [["Okonoma", "Lapacompris"]])
        XCTAssertEqual(bench.engine.startedLocales.map(\.identifier), ["fr-FR"])
    }

    /// The instruction is used as heard, trimmed, with the speaker's own
    /// spellings put back — the same replacements a dictation gets.
    func testTheInstructionIsRunAsHeardWithItsReplacements() async {
        let bench = Bench(events: [.final("  traduis pour Okuma  ")],
                          vocabulary: "Okuma → Okonoma")
        await bench.speak()
        XCTAssertEqual(bench.ran, ["traduis pour Okonoma"])
    }

    // MARK: - Nothing to run

    /// A key held on a silence: the panel says it heard nothing rather than
    /// running an empty instruction, then takes itself off the screen.
    func testNothingHeardSaysSoThenClosesThePanel() async {
        let bench = Bench(events: [.final("   ")], durations: .brief)
        await bench.speak()

        XCTAssertEqual(bench.session.phase, .instructionNotHeard(reason: nil))
        XCTAssertTrue(bench.ran.isEmpty)
        await bench.wait { bench.closed == 1 }
        XCTAssertEqual(bench.closed, 1)
    }

    /// The microphone gives up: its own message is shown, then the panel
    /// closes itself as it does on a silence. Nothing is left paused while
    /// the message is up.
    func testAnEngineFailureSaysWhyThenClosesThePanel() async {
        let bench = Bench(events: [.failed(.microphoneDenied)], durations: .brief)
        bench.coordinator.keyDown()
        await bench.cycleEnds()

        XCTAssertEqual(bench.session.phase,
                       .instructionNotHeard(reason: SpeechEngineError.microphoneDenied.localizedDescription))
        XCTAssertFalse(bench.media.leftPaused)
        await bench.wait { bench.closed == 1 }
        XCTAssertEqual(bench.closed, 1)
    }

    /// A panel that has moved on keeps its phase: a tap must not hand back a
    /// field over an instruction already on its way. Nothing selected is no
    /// longer such a phase — the panel goes on listening over nothing.
    func testATapLeavesAPanelThatMovedOnAlone() async {
        let bench = Bench()
        bench.coordinator.keyDown()
        await bench.settle { bench.engine.starts == 1 }
        bench.session.phase = .streaming  // the engine stopped by itself, and it went out

        bench.hold(for: 0.1)
        bench.coordinator.keyUp()

        XCTAssertEqual(bench.session.phase, .streaming)
        XCTAssertEqual(bench.typed, 0)
    }

    // MARK: - What was playing

    /// Music talking over the voice is what makes an instruction hard to
    /// hear: whatever plays is paused while the key is held, and resumed on
    /// release, after the microphone has closed.
    func testWhatPlaysPausesWhileItListensAndResumesOnRelease() async {
        let bench = Bench()
        bench.coordinator.keyDown()
        await bench.settle { bench.media.commands == [.pause] }
        XCTAssertEqual(bench.media.commands, [.pause])

        bench.hold(for: 1)
        bench.coordinator.keyUp()
        XCTAssertEqual(bench.media.commands, [.pause, .play])
        XCTAssertEqual(bench.media.microphoneClosesAtResume, [1])

        await bench.cycleEnds()
        XCTAssertEqual(bench.ran, ["traduis en espagnol"])
        XCTAssertEqual(bench.media.commands, [.pause, .play])
        XCTAssertEqual(bench.media.reads, 1)
    }

    /// Nothing playing, nothing sent — above all no play at the end.
    func testNothingPlayingSendsNoCommandAtAll() async {
        let bench = Bench(playing: false)
        await bench.speak()
        XCTAssertEqual(bench.media.reads, 1)
        XCTAssertEqual(bench.media.commands, [])
    }

    /// A tap is over long before a slow read answers: the field comes back,
    /// and the answer, when it arrives, pauses nothing.
    func testATapBeforeTheReadAnswersPausesNothing() async {
        let bench = Bench(readsWait: true)
        bench.coordinator.keyDown()
        await bench.settle { bench.engine.starts == 1 && bench.media.reads == 1 }
        let read = bench.pauser.read

        bench.hold(for: 0.1)
        bench.coordinator.keyUp()
        XCTAssertEqual(bench.session.phase, .askingInstruction)

        bench.media.answerRead()
        await read?.value
        XCTAssertEqual(bench.media.commands, [])
    }

    /// A tap once the music is paused gives it back with the field.
    func testATapAfterThePauseResumes() async {
        let bench = Bench()
        bench.coordinator.keyDown()
        await bench.settle { bench.media.commands == [.pause] }

        bench.hold(for: 0.1)
        bench.coordinator.keyUp()
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// Esc, another shortcut, the panel closed by hand, quitting: whatever
    /// takes the panel away ends the listening, and resumes the music once.
    func testThePanelGoingAwayResumesExactlyOnce() async {
        let bench = Bench()
        bench.coordinator.keyDown()
        await bench.settle { bench.media.commands == [.pause] }

        bench.coordinator.cancel()
        bench.coordinator.cancel()

        XCTAssertEqual(bench.media.commands, [.pause, .play])
        XCTAssertEqual(bench.media.microphoneClosesAtResume, [1])
        XCTAssertEqual(bench.engine.cancels, 1)
        XCTAssertTrue(bench.ran.isEmpty)
    }

    /// The microphone giving up after the pause resumes at once, and the
    /// panel leaving later resumes nothing more.
    func testAFailureResumesAtOnceAndOnlyOnce() async {
        let bench = Bench(durations: .brief)
        bench.coordinator.keyDown()
        await bench.settle { bench.media.commands == [.pause] }

        bench.engine.say(.failed(.recognizer("timeout")))
        await bench.cycleEnds()
        XCTAssertEqual(bench.media.commands, [.pause, .play])

        await bench.wait { bench.closed == 1 }
        bench.coordinator.cancel()
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// An engine that stops by itself, the key still down, has closed the
    /// microphone all the same: the music resumes before the instruction
    /// runs, and the release that follows resumes nothing more.
    func testWhenTheEngineStopsByItselfTheMusicResumes() async {
        let bench = Bench()
        bench.coordinator.keyDown()
        await bench.settle { bench.media.commands == [.pause] }

        bench.engine.say(.final("traduis en espagnol"))
        await bench.cycleEnds()
        XCTAssertEqual(bench.ran, ["traduis en espagnol"])
        XCTAssertEqual(bench.media.commands, [.pause, .play])

        bench.hold(for: 1)
        bench.coordinator.keyUp()
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// A key held on a silence ends like any other hold: resumed once.
    func testNothingHeardResumesOnce() async {
        let bench = Bench(events: [.final("   ")], durations: .brief)
        await bench.speak()
        XCTAssertEqual(bench.media.commands, [.pause, .play])

        await bench.wait { bench.closed == 1 }
        bench.coordinator.cancel()
        XCTAssertEqual(bench.media.commands, [.pause, .play])
    }

    /// Switched off in Settings: the state isn't even read.
    func testWithTheSettingOffNothingIsReadNorSent() async {
        let bench = Bench(pausesMedia: false)
        await bench.speak()
        bench.coordinator.cancel()
        XCTAssertEqual(bench.media.reads, 0)
        XCTAssertEqual(bench.media.commands, [])
        XCTAssertEqual(bench.ran, ["traduis en espagnol"])
    }

    // MARK: - Permissions

    /// Without the microphone the shortcut is what it always was: a tap
    /// opens the field, nothing is listened to, and no prompt interrupts a
    /// gesture that asked for none.
    func testWithoutTheMicrophoneATapStillTypesTheInstruction() async {
        let bench = Bench(microphoneGranted: false)
        bench.coordinator.keyDown()
        bench.hold(for: 0.1)
        bench.coordinator.keyUp()

        XCTAssertEqual(bench.typed, 1)
        XCTAssertEqual(bench.listens, 0)
        XCTAssertEqual(bench.engine.starts, 0)
        XCTAssertEqual(bench.permissionRequests, 0)
        XCTAssertEqual(bench.media.reads, 0)
    }

    /// Held, it asks for the microphone and explains itself when it is
    /// refused. Nothing is heard on this press — the prompts are modal and
    /// the key is long released by the time they are answered — so this one
    /// asks and the next one speaks.
    func testAHoldWithoutTheMicrophoneAsksForIt() async {
        let bench = Bench(microphoneGranted: false)
        bench.coordinator.keyDown()
        bench.hold(for: 1)
        bench.coordinator.keyUp()
        await bench.coordinator.permission?.value

        XCTAssertEqual(bench.permissionRequests, 1)
        XCTAssertEqual(bench.explanations, 1)
        XCTAssertEqual(bench.engine.starts, 0)
        XCTAssertEqual(bench.typed, 0)
    }

    /// Without Accessibility there is nothing to transform: the press has
    /// already said so, and the microphone stays shut.
    func testWithoutAccessibilityNothingIsListenedTo() async {
        let bench = Bench(opensPanel: false)
        bench.coordinator.keyDown()
        bench.hold(for: 1)
        bench.coordinator.keyUp()

        XCTAssertEqual(bench.engine.starts, 0)
        XCTAssertEqual(bench.media.reads, 0)
        XCTAssertEqual(bench.typed, 0)
        XCTAssertTrue(bench.ran.isEmpty)
    }
}

// MARK: - The bench

/// One coordinator and the fakes it was built with, plus what a test needs
/// to drive it: a clock it moves by hand, the session the panel handed back,
/// and what each closure was asked.
@MainActor
private final class Bench: AsyncWaiting {
    let engine: FakeSpeechEngine
    var coordinator: SpokenInstructionCoordinator { built }
    private var built: SpokenInstructionCoordinator!

    /// The session a real free action would have opened on the selection.
    let session = CorrectionSession(request: .awaitingInstruction)
    /// How many times the panel was opened listening, and how many times it
    /// fell back to the field where the instruction is typed.
    var listens = 0
    var typed = 0
    /// Every instruction the free action was handed, in order.
    var ran: [String] = []
    /// How many times the panel was taken off the screen.
    var closed = 0
    /// What the settings hold right now.
    var vocabulary: DictationVocabulary
    let microphoneGranted: Bool
    var permissionRequests = 0
    var explanations = 0
    /// What plays on the Mac, and the pauser the coordinator tells about
    /// each listening: the commands land in the first, the read under way is
    /// the second's.
    let media: FakeMediaPlayback
    let pauser: MediaPauser

    private var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init(events: [TranscriptEvent] = [.partial("traduis"),
                                      .partial("traduis en espagnol"),
                                      .final("traduis en espagnol")],
         vocabulary: String = "",
         opensPanel: Bool = true,
         microphoneGranted: Bool = true,
         playing: Bool = true,
         readsWait: Bool = false,
         pausesMedia: Bool = true,
         durations: PanelMessageDurations = .standard) {
        self.microphoneGranted = microphoneGranted
        self.vocabulary = DictationVocabulary(parsing: vocabulary)
        let engine = FakeSpeechEngine(events)
        self.engine = engine
        let media = FakeMediaPlayback(playing: playing, readsWait: readsWait)
        media.microphoneCloses = { engine.stops + engine.cancels }
        self.media = media
        pauser = MediaPauser(playback: media.playback)
        let session = self.session
        built = SpokenInstructionCoordinator(
            engine: engine,
            panel: SpokenInstructionPanel(
                type: { [weak self] in self?.typed += 1 },
                listen: { [weak self] in
                    guard let self, opensPanel else { return nil }
                    listens += 1
                    session.instruction = ""
                    session.phase = .listeningInstruction
                    return session
                },
                run: { [weak self] instruction in self?.ran.append(instruction) },
                close: { [weak self] in self?.closed += 1 }
            ),
            language: { .frFR },
            vocabulary: { [weak self] in self?.vocabulary ?? .empty },
            microphone: MicrophoneGate(
                isGranted: { [weak self] in self?.microphoneGranted ?? false },
                request: { [weak self] in
                    self?.permissionRequests += 1
                    return self?.microphoneGranted ?? false
                },
                showExplanation: { [weak self] in self?.explanations += 1 }
            ),
            pauser: pauser,
            pausesMedia: { pausesMedia },
            durations: durations,
            now: { [weak self] in self?.clock ?? .distantPast }
        )
    }

    /// Moves the clock forward: that's how long the key stayed down.
    func hold(for seconds: TimeInterval) { clock += seconds }

    /// A full gesture: press, speak, release, and wait for the instruction
    /// to reach the free action.
    func speak() async {
        coordinator.keyDown()
        await settle { engine.starts == 1 }
        if !media.readsWait { await pauser.read?.value }
        hold(for: 1)
        coordinator.keyUp()
        await cycleEnds()
    }

    /// Waits for the cycle under way to end. One that never does fails its
    /// test instead of hanging the suite.
    func cycleEnds(seconds: TimeInterval = 2,
                   file: StaticString = #filePath, line: UInt = #line) async {
        guard let cycle = coordinator.cycle else { return }
        let ceiling = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            XCTFail("the instruction never ended", file: file, line: line)
            cycle.cancel()
        }
        await cycle.value
        ceiling.cancel()
    }

}

private extension PanelMessageDurations {
    /// Short enough for a test to watch a panel close itself without waiting
    /// four seconds for it.
    static let brief = PanelMessageDurations(empty: .milliseconds(5),
                                                             failure: .milliseconds(5))
}

