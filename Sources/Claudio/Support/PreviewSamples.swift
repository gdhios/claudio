import AppKit

/// What the previews show: fixed texts, readings and a track, the same on
/// every machine. Nothing here reads this Mac or the network.
@MainActor
enum PreviewSamples {
    /// Sample text for previews: an email written quickly, with the typos
    /// that come with it. It follows the interface's language: an English
    /// capture whose selection is in French wouldn't show what it advertises.
    static var sampleText: String {
        loc("Bonjour, je voulait savoir si tu pouvait m'envoyer les document avant demain matin. merci d'avance",
            en: "Hi, i wanted to know if you could send me the document before tomorow morning. thanks in advance")
    }

    /// Sample instruction for the custom-action previews.
    static var sampleInstruction: String {
        loc("Traduis en espagnol", en: "Translate to Spanish")
    }

    /// The same instruction being said rather than typed, caught
    /// mid-sentence: the shortcut is still held.
    static var spokenInstruction: String {
        loc("Traduis ce message en ", en: "Translate this message to ")
    }

    /// A request made with nothing selected, about the track playing.
    static var shareInstruction: String {
        loc("Écris un message pour partager ce que j'écoute",
            en: "Write a message to share what I'm listening to")
    }

    /// Its answer: a message ready to paste, which leans on the track.
    static var sharedTrackMessage: String {
        loc("En ce moment j'écoute « 真夜中のジョーク » de Takako Mamiya, extrait de LOVE TRIP (1982). De la city pop japonaise comme on n'en fait plus, à écouter d'urgence.",
            en: "Right now I'm listening to “真夜中のジョーク” by Takako Mamiya, from LOVE TRIP (1982). Japanese city pop like they don't make anymore, give it a listen.")
    }

    /// A voice starting in a quiet room: flat, then a phrase with its rises
    /// and a breath. Fixed values, so the shot is the same on every machine.
    static var voiceLevels: LevelHistory {
        let readings: [Float] = [0, 0, 0.02, 0, 0.05, 0.1, 0.35, 0.62, 0.48, 0.7, 0.85, 0.55,
                                 0.3, 0.12, 0.08, 0.4, 0.66, 0.9, 0.72, 0.5, 0.58, 0.8, 0.45, 0.2,
                                 0.1, 0.3, 0.55, 0.75, 0.6, 0.38, 0.52, 0.68]
        return readings.reduce(LevelHistory()) { $0.adding($1) }
    }

    /// A dictation as it comes out of speech recognition: no punctuation, a
    /// hesitation, and the speaker correcting themselves.
    static var spokenText: String {
        loc("euh bonjour je voulais te dire que la réunion de mardi non mercredi est décalée à quatorze heures",
            en: "uh hi i wanted to tell you that tuesday's no wednesday's meeting is pushed to two pm")
    }

    /// The same dictation being tidied up, caught mid-sentence.
    static var tidiedText: String {
        loc("Bonjour, je voulais te dire que la réunion de ",
            en: "Hi, I wanted to tell you that Wednesday's meeting ")
    }

    /// The long text "Tell me more" shows in place of the notes.
    static var sampleEssay: String {
        loc("LOVE TRIP paraît en novembre 1982 chez Columbia, au cœur de la vague city pop : Takako Mamiya, chanteuse de jazz formée dans les clubs de Tokyo, l'enregistre avec des musiciens de studio et des arrangements soignés. Ce sera son unique album.\n\nL'album se distingue par son élégance retenue : des tempos modérés, des cuivres discrets, une voix posée qui ne force jamais. Passé presque inaperçu à sa sortie, il devient culte trente ans plus tard, quand internet redécouvre la city pop.\n\nPour commencer : « 真夜中のジョーク », puis « All Or Nothing ».",
            en: "LOVE TRIP came out in November 1982 on Columbia, at the heart of the city pop wave: Takako Mamiya, a jazz singer trained in Tokyo's clubs, recorded it with studio musicians and polished arrangements. It would be her only album.\n\nThe album stands out for its restrained elegance: moderate tempos, discreet horns, a poised voice that never forces. Almost unnoticed on release, it became a cult record thirty years later, when the internet rediscovered city pop.\n\nStart with “真夜中のジョーク”, then “All Or Nothing”.")
    }

    /// What MusicBrainz says of the sample track (captured 2026-10-02):
    /// the player names the album, so the line shows the year and type.
    static var sampleFacts: TrackFacts {
        TrackFacts(recordingID: "783dfef9-87f4-4056-b944-c7ae624d5964",
                   releaseGroupID: "3b03f2df-1fc0-4572-8b90-8f952a2a9fcb",
                   albumTitle: "LOVE TRIP", primaryType: "Album", secondaryTypes: [],
                   firstReleaseDate: "1982-11-25")
    }

    /// A cover drawn here rather than read anywhere: the same square on
    /// every machine, the night-blue of the sample album.
    static var sampleArtwork: NSImage {
        let size = NSSize(width: 250, height: 250)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.36, alpha: 1),
                                NSColor(calibratedRed: 0.72, green: 0.36, blue: 0.48, alpha: 1)])?
                .draw(in: rect, angle: -60)
            NSColor(calibratedWhite: 1, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 70, dy: 70)).fill()
            return true
        }
    }

    /// A track whose metadata isn't in the Latin alphabet: the card shows it
    /// as the player gives it.
    static func sampleTrack(playing: Bool) -> NowPlayingTrack {
        NowPlayingTrack(title: "真夜中のジョーク", artist: "間宮貴子", album: "LOVE TRIP",
                        appName: "Spotify", bundleID: "com.spotify.client",
                        isPlaying: playing)
    }

    /// Galette as if installed, so its buttons show on every machine: the
    /// generic app icon stands in for its own, and no player is a browser.
    static var previewGalette: GaletteApp {
        GaletteApp(icon: NSWorkspace.shared.icon(for: .applicationBundle), browsers: [])
    }

    /// Notes of the kind the prompt asks for: who, where from, one fact.
    static var sampleNotes: String {
        loc("Takako Mamiya est une chanteuse japonaise de city pop. LOVE TRIP, paru en 1982, est son seul album : longtemps confidentiel, il est devenu culte avec le regain d'intérêt pour la city pop sur internet.",
            en: "Takako Mamiya is a Japanese city pop singer. LOVE TRIP, released in 1982, is her only album: long overlooked, it became a cult favourite with the online revival of city pop.")
    }
}
