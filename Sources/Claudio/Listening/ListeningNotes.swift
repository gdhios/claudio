import Foundation

/// What Claude is asked about the track playing: the prompt, the message,
/// the model and the room its answer gets. Fixed rather than set in
/// Settings — there is nothing here anyone should have to tune.
enum ListeningNotes {
    /// Sonnet rather than Haiku: here being right matters more than being
    /// fast, and Haiku knows less about little-known catalogues and invents
    /// more readily. Three sentences cost next to nothing either way.
    /// Sonnet 5.5 since 2026-10-02: same price as Sonnet 5.
    static let model: ModelChoice = .claude(.sonnet55)

    /// Three short sentences fit many times over; a runaway answer doesn't.
    static let maxTokens = 400

    /// The track as the player described it, tagged: only the fields it
    /// gave, and not whether it's paused.
    static func userMessage(for track: NowPlayingTrack) -> String {
        track.promptBlock(tag: "morceau")
    }

    /// Written once, in French like every prompt in the app; only its last
    /// line follows the interface language, so the notes read in the same
    /// language as the panel around them.
    static func system(language: AppLanguage = AppSettings.language) -> String {
        let answerLanguage = language.showsEnglish ? "anglais" : "français"
        return """
            Tu es Claudio, un petit assistant de barre de menus sur macOS. L'utilisateur écoute le \
            contenu décrit entre balises <morceau> et te demande ce que c'est.

            Tâche : en trois phrases courtes au plus, présente ce qu'il écoute : qui est l'artiste, \
            d'où vient le morceau (album, année, genre ou courant), et un fait marquant si tu en \
            connais un de façon sûre.

            Méthode :
            - Les métadonnées viennent du lecteur. Si le titre ressemble à un titre de vidéo \
            (« Artiste - Titre (Official Video) », un nom de chaîne en guise d'artiste), déduis-en \
            le morceau.
            - Si ce n'est pas de la musique (podcast, vidéo, livre audio), dis ce que c'est en une \
            phrase.
            - Tu n'inventes rien : aucune date, aucun classement, aucune collaboration, aucune \
            anecdote dont tu n'es pas sûr. Si tu ne connais pas ce morceau ou cet artiste, dis-le en \
            une phrase et tiens-t'en à ce que disent les métadonnées.

            Règles impératives :
            - Texte brut : ni titre, ni gras, ni puces, ni préambule du type « Tu écoutes ».
            - N'ouvre pas en répétant le titre et l'artiste : le panneau les affiche déjà au-dessus \
            de ta réponse.
            - Réponds en \(answerLanguage).
            """
    }
}
