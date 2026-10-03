import Foundation

@MainActor
final class CorrectionSession: ObservableObject {
    enum Phase: Equatable {
        case capturing
        /// Palette: the selection is captured, the action is chosen in the panel.
        case choosingAction
        /// Custom action: the selection is captured, the instruction is entered in the panel.
        case askingInstruction
        /// Custom action with the shortcut held: the selection is captured,
        /// the microphone is open, and the instruction is being said rather
        /// than typed. The words land in `instruction` as they come.
        case listeningInstruction
        /// The instruction was to be spoken and wasn't: nothing was heard,
        /// or the microphone gave up — its reason, when it had one. The
        /// panel says so, then closes itself.
        case instructionNotHeard(reason: String?)
        case streaming
        case done
        case noSelection
        case missingKey
        case error(String)
    }

    @Published private(set) var request: ClaudioRequest
    /// The palette opens between the capture and the call: the request is then
    /// only a placeholder, replaced by the chosen row.
    let opensPalette: Bool

    init(request: ClaudioRequest, opensPalette: Bool = false) {
        self.request = request
        self.opensPalette = opensPalette
    }

    /// Convenience for calls that start from a catalog entry.
    convenience init(action: ClaudioAction) { self.init(request: action.request) }

    /// The custom action only learns its request once the instruction is confirmed.
    func adopt(_ request: ClaudioRequest) { self.request = request }

    @Published var phase: Phase = .capturing
    @Published var correctedText = ""
    @Published var truncated = false
    @Published var justCopied = false
    /// The track the request went out with, `nil` when none did: a catalog
    /// action, nothing playing, nothing sent yet. The line under the answer
    /// names this one — what was sent, not what plays now.
    @Published private(set) var sentTrack: NowPlayingTrack?
    /// Galette, when the panel found it as it opened — only for a request
    /// that may send the track. `nil` without Galette.
    @Published var galette: GaletteApp?
    /// Instruction currently being typed — or said, when the shortcut is
    /// held: both gestures fill the same field (custom action).
    @Published var instruction = ""
    /// The microphone's recent loudness while the instruction is spoken,
    /// drawn as a waveform: the proof it hears, before the first word shows up.
    @Published var levels = LevelHistory()
    /// The key came up and the microphone with it, while the engine still
    /// has its last word to say. Without this the pill would go on claiming
    /// to listen over a waveform that has gone flat.
    @Published var listeningEnded = false
    /// Palette input: filters the catalog, and serves as the instruction if it's
    /// the custom-action row that gets launched.
    @Published var paletteQuery = "" {
        // The filter changed, so does the list. Only then: the field also
        // hands its text back, unchanged, when Return ends the editing, and
        // going back to the top on that write made ↓ then Enter launch the
        // first row instead of the highlighted one.
        didSet { if paletteQuery != oldValue { paletteSelection = 0 } }
    }
    @Published var paletteSelection = 0
    var originalText = ""
    var maxTokensMultiplier = 1

    /// Whether the capture found anything to work on. Only ever false past
    /// the capture for the palette and the custom action: a catalog action
    /// stops at `noSelection`.
    var hasSelection: Bool { !originalText.isEmpty }

    /// Where the session goes once the capture is back, `nil` when it waits
    /// on nothing and the request goes out at once.
    ///
    /// With nothing selected, a catalog action had the selection for
    /// material, and says there was none. The palette still opens, on what
    /// works without a selection: opening it asks a question rather than
    /// giving an order. And the custom action still asks for its
    /// instruction, which, with no text to apply it to, is a request made to
    /// Claudio.
    var phaseAfterCapture: Phase? {
        guard hasSelection || request.worksWithoutSelection else { return .noSelection }
        if opensPalette { return .choosingAction }
        guard request.needsInstruction else { return nil }
        // The shortcut held rather than tapped: the panel keeps listening
        // instead of asking for the instruction to be typed.
        return phase == .listeningInstruction ? .listeningInstruction : .askingInstruction
    }

    /// What the panel says while the answer streams. The custom action on
    /// nothing selected transforms nothing: it writes an answer, and says so.
    var progressLabel: String {
        guard !hasSelection, case .free = request.origin else { return request.progressLabel }
        return loc("Rédaction…", en: "Writing…")
    }

    /// Palette rows for the current input.
    var paletteRows: [PaletteRow] {
        PaletteCatalog.rows(matching: paletteQuery, hasSelection: hasSelection)
    }

    /// Pointer position when the palette opens. As long as it hasn't
    /// moved, hovering over it selects nothing: the panel opens near the cursor,
    /// and a row it happens to cover would otherwise grab the selection with no
    /// hand involved.
    private var hoverOrigin: CGPoint?

    /// When the palette appears: hovering is pending a movement.
    func armHover(at location: CGPoint) { hoverOrigin = location }

    /// `true` if this hover comes from a hand that has moved. The first real
    /// movement hands the mouse back to its job, for good.
    func acceptsHover(at location: CGPoint) -> Bool {
        guard let origin = hoverOrigin else { return true }
        guard hypot(location.x - origin.x, location.y - origin.y) > 2 else { return false }
        hoverOrigin = nil
        return true
    }

    /// Moves the selection without leaving the list: once at the bottom, it stays there.
    func movePaletteSelection(by delta: Int) {
        let count = paletteRows.count
        guard count > 0 else { return }
        paletteSelection = min(max(paletteSelection + delta, 0), count - 1)
    }

    /// Index of the row a digit launches, or `nil` if the key should
    /// go its own way. The rank shown in front of each row is therefore typed as
    /// is: that's what it promises. Without ⌘ it only launches, though, as long as
    /// nothing has been typed yet: past the first keystroke the field is dictating an
    /// instruction, and "3" has to be written into it. A leading space is then enough
    /// to start an instruction with a digit.
    func paletteIndex(forRank rank: Int, withCommand: Bool) -> Int? {
        guard phase == .choosingAction else { return nil }
        guard withCommand || paletteQuery.isEmpty else { return nil }
        let index = rank - 1
        return paletteRows.indices.contains(index) ? index : nil
    }

    var canPaste: Bool { phase == .done && !correctedText.isEmpty }

    /// The Galette buttons on the line naming the track sent: none without
    /// Galette, before a track went out, or for one that gives nothing to open.
    var galetteLinks: [GaletteLink] {
        guard let galette, let sentTrack else { return [] }
        return galette.links(for: sentTrack)
    }

    /// Usable instruction: the "Run" button and ⏎ stay inert without it.
    var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The instruction is still being given — typed in the field, or said
    /// into the microphone. Both end the same way: the request adopts it.
    var isEnteringInstruction: Bool {
        phase == .askingInstruction || phase == .listeningInstruction
    }

    /// The shortcut was tapped, not held: the instruction goes back to being
    /// typed, in the panel the press already opened over the same selection,
    /// or over nothing. Only from the listening phase — an engine that
    /// stopped by itself may have sent the instruction on already.
    ///
    /// The word or two caught before the key came up are dropped: they were
    /// never meant to be the instruction, and the field starts empty as ever.
    func typeInstructionInstead() {
        guard phase == .listeningInstruction else { return }
        instruction = ""
        phase = .askingInstruction
    }

    // MARK: - Stream

    /// Fragments received since the last publish. The SSE stream delivers
    /// several dozen a second; republishing `correctedText` on each one
    /// triggers a full re-layout of the text, growing more costly as it
    /// gets longer. That's what was saturating the main loop and
    /// making the window advance in jerks on long answers. So we
    /// accumulate, and publish at a fixed cadence.
    private var streamBuffer = ""
    private var flushScheduled = false

    /// Publish cadence: short enough for the text to feel alive,
    /// long enough to let the layout pass happen in between.
    static let streamFlushInterval: Duration = .milliseconds(60)

    /// Opens a response: buffer cleared, text reset. `track` is the one the
    /// request went out with, `nil` when none did.
    func beginStreaming(sending track: NowPlayingTrack? = nil) {
        streamBuffer = ""
        flushScheduled = false
        correctedText = ""
        truncated = false
        justCopied = false
        sentTrack = track
        phase = .streaming
    }

    /// Receives a fragment. The first one goes out immediately: the panel must
    /// react from the very first word; the following ones wait for the next flush.
    func appendStreamed(_ piece: String) {
        streamBuffer += piece
        guard !correctedText.isEmpty else {
            flushStreamed()
            return
        }
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: CorrectionSession.streamFlushInterval)
            self?.flushStreamed()
        }
    }

    /// Publishes whatever is waiting in the buffer.
    func flushStreamed() {
        flushScheduled = false
        guard !streamBuffer.isEmpty else { return }
        correctedText += streamBuffer
        streamBuffer = ""
    }

    /// End of stream: the full text replaces whatever went out along the way, and
    /// whatever remained in the buffer with it.
    func finishStreaming(with text: String, truncated: Bool) {
        streamBuffer = ""
        flushScheduled = false
        correctedText = text
        self.truncated = truncated
        phase = .done
    }
}
