@testable import Claudio

extension CorrectionSession {
    /// The row Enter launches: the highlighted one, read the way
    /// `CorrectionCoordinator.launchPaletteRow(at:)` reads it, so a stale
    /// index gives no row rather than another one.
    var selectedPaletteRow: PaletteRow? {
        let rows = paletteRows
        return rows.indices.contains(paletteSelection) ? rows[paletteSelection] : nil
    }
}
