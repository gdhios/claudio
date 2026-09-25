import SwiftUI

/// The line under an answer that went out with the track playing: which
/// track, so what the answer says of it can be checked at a glance — and,
/// at its end, the way to it in Galette. Only ever shown for a track that
/// was sent, never for one merely playing.
struct SentTrackLine: View {
    let track: NowPlayingTrack
    var textSize: PanelTextSize = .normal
    /// Galette's buttons for the track, `nil` for none.
    var galette: GaletteButtons? = nil

    /// « ♪ Titre — Artiste »: the track the way "What's playing?" copies it.
    static func text(for track: NowPlayingTrack) -> String { "♪ \(track.copyLine)" }

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.text(for: track))
                .font(.system(size: textSize.points(11)))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let galette {
                galette
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
