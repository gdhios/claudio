import Foundation

/// The custom action with nothing selected: there is no text to apply a task
/// to, so the instruction becomes a request made to Claudio, answered with a
/// text ready to paste where the cursor is — "write an email to move the
/// meeting", "what is this track?".
///
/// A prompt of its own rather than the transformation's with a line on top:
/// "apply this task to the text, and nothing else" over a request with no
/// text is an order under a contrary one, and the order wins.
enum FreeRequest {
    /// The tag the track playing travels in, after the request or the text.
    /// Context, never an instruction: both prompts present it as something
    /// to use only when the request is about it.
    static let trackTag = "morceau_en_cours"

    static let system = """
        Tu es Claudio, un petit assistant de barre de menus sur macOS. L'utilisateur te fait une \
        demande entre balises <consigne>. Réponds-y directement : ta réponse sera collée telle \
        quelle là où il écrit.

        Méthode :
        - Fais ce qui est demandé, rien de plus : un message demandé est un message prêt à \
        envoyer, une question appelle une réponse courte.
        - Un bloc <morceau_en_cours> peut suivre : c'est ce que l'utilisateur écoute en ce \
        moment. Ne t'en sers que si la demande en parle. Tu n'inventes rien sur ce morceau : ce \
        dont tu n'es pas sûr, tu ne le dis pas.
        - Réponds dans la langue de la demande.

        Règles impératives :
        - Texte brut, prêt à coller : ni préambule, ni commentaire, ni guillemets d'encadrement, \
        ni markdown (puces « - » et retours à la ligne bienvenus).
        """

    /// The request, tagged as a selection is: the prompt knows where it
    /// starts and where it ends, whatever it says.
    static func userMessage(instruction: String) -> String {
        """
        <consigne>
        \(instruction)
        </consigne>
        """
    }
}
