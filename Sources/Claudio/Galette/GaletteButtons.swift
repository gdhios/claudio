import SwiftUI

/// Galette's icon, then « Artiste » and « Album »: small pills that open the
/// track in Galette. On "What's playing?"'s card, and on the line naming the
/// track a request went out with.
struct GaletteButtons: View {
    let icon: NSImage
    let links: [GaletteLink]
    let onOpen: (GaletteLink) -> Void

    /// `nil` when there is nothing to show: no Galette on this Mac, or
    /// nothing in the track to open.
    init?(galette: GaletteApp?, links: [GaletteLink], onOpen: @escaping (GaletteLink) -> Void) {
        guard let galette, !links.isEmpty else { return nil }
        self.icon = galette.icon
        self.links = links
        self.onOpen = onOpen
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            ForEach(links, id: \.self) { link in
                Button(link.buttonTitle) { onOpen(link) }
                    .buttonStyle(SmallPillButtonStyle())
                    .help(link.buttonHelp)
            }
        }
        .fixedSize()
    }
}

extension GaletteLink {
    /// What its button says: which side of the track it opens.
    var buttonTitle: String {
        switch self {
        case .artist: loc("Artiste", en: "Artist")
        case .album: loc("Album", en: "Album")
        }
    }

    var buttonHelp: String {
        switch self {
        case .artist: loc("Ouvrir l'artiste dans Galette", en: "Open the artist in Galette")
        case .album: loc("Ouvrir l'album dans Galette", en: "Open the album in Galette")
        }
    }
}
