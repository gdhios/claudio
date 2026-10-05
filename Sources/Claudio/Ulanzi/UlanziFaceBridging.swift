import Foundation

/// What the face fleet asks of one clock's bridge, and no more: narrow, so
/// a test hands the fleet bridges of its own. `UlanziBridge` is the real
/// one.
@MainActor
protocol UlanziFaceBridging: AnyObject {
    var status: UlanziBridge.Status { get }
    var onStatusChange: ((UlanziBridge.Status) -> Void)? { get set }
    /// The last call queued for the clock: a bridge that starts on the same
    /// clock after this one stopped waits for it.
    var sending: Task<Void, Never>? { get }
    func correctionSessionChanged(_ session: CorrectionSession?)
    func dictationSessionChanged(_ session: DictationSession?)
    /// Claudio smiles on the clock for a moment.
    func test()
    /// Puts the face away, and follows nothing more.
    func stop()
    /// Quitting: lets go, and hands back the off still to send, nil when
    /// the face can't be up.
    func letGoForQuit() -> UlanziBridge.PutAway?
}

extension UlanziBridge: UlanziFaceBridging {}
