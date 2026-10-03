import SwiftUI

/// The Music tab: what "What's playing?" asks Claude — which model, how
/// much — what completes his notes: the MusicBrainz facts, the cover; and
/// the long text's own model. The models are the same settings as the
/// Models tab's rows. Not here, on purpose: the notes' language (the
/// interface's), their system prompt (it carries the "invent nothing"
/// rule), the sources' budget.
@MainActor
struct MusicPane: View {
    // A preview shows fixed settings rather than this Mac's: the shot has to
    // be the same on every machine.
    @State private var detail = PreviewRun.isActive ? ListeningDetail.threeSentences : AppSettings.listeningDetail()
    @State private var musicBrainz = PreviewRun.isActive ? true : AppSettings.musicBrainzEnabled()
    @State private var showsArtwork = PreviewRun.isActive ? true : AppSettings.showsArtwork()
    @State private var localModels: [String] = []

    var body: some View {
        Form {
            Section {
                ModelSlotRow(slot: .listening, localModels: localModels)
                Picker(loc("Longueur des notes", en: "Length of the notes"), selection: $detail) {
                    ForEach(ListeningDetail.allCases, id: \.self) { detail in
                        Text(detail.displayName).tag(detail)
                    }
                }
                .onChange(of: detail) { AppSettings.setListeningDetail(detail) }
                Text(loc("Claude présente l'artiste, d'où vient le morceau et un fait marquant, sans rien inventer. La longueur vaut pour la prochaine écoute.",
                         en: "Claude introduces the artist, where the track comes from and one notable fact, inventing nothing. The length applies to the next listening."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(loc("Notes de Claude", en: "Claude's notes"))
            }

            Section {
                ModelSlotRow(slot: .essay, localModels: localModels)
                Text(loc("Le texte long de « Sur l'album » et « Sur l'artiste ». Avec MusicBrainz, Claude reçoit d'abord la fiche de l'artiste et sa discographie datée, et ne cite que ce qui s'y trouve. Un petit modèle invente sur un catalogue peu connu : Sonnet 5.5 au moins.",
                         en: "The long text of “About the album” and “About the artist”. With MusicBrainz, Claude first gets the artist's record and dated discography, and cites nothing beyond them. A small model invents on a little-known catalogue: Sonnet 5.5 at least."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(loc("En savoir plus", en: "Tell me more"))
            }

            Section {
                Toggle(loc("Compléter avec MusicBrainz et Deezer", en: "Complete with MusicBrainz and Deezer"), isOn: $musicBrainz)
                    .onChange(of: musicBrainz) { AppSettings.setMusicBrainzEnabled(musicBrainz) }
                Text(loc("Album d'origine, type et année de première sortie, affichés sous le morceau et transmis à Claude pour qu'il ne les devine pas. Seuls le titre, l'artiste et l'album sont envoyés à musicbrainz.org, base communautaire gratuite, avec l'identifiant Claudio/\(Bundle.main.shortVersion), puis à api.deezer.com quand MusicBrainz ne connaît pas encore le disque. Rien n'attend leur réponse.",
                         en: "Album of origin, type and year of first release, shown under the track and given to Claude so he doesn't guess them. Only the title, artist and album are sent to musicbrainz.org, a free community database, as Claudio/\(Bundle.main.shortVersion), then to api.deezer.com when MusicBrainz doesn't know the record yet. Nothing waits for their answer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(loc("Afficher la pochette", en: "Show the cover"), isOn: $showsArtwork)
                    .onChange(of: showsArtwork) { AppSettings.setShowsArtwork(showsArtwork) }
                Text(loc("Celle du lecteur quand il la donne (Spotify), sinon celle du Cover Art Archive quand MusicBrainz a reconnu le morceau.",
                         en: "The player's when it gives one (Spotify), else the Cover Art Archive's once MusicBrainz has recognised the track."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(loc("Compléments", en: "Extras"))
            }
        }
        .formStyle(.grouped)
        .task { localModels = await LocalModels.discover() }
    }
}
