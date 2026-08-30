import XCTest
@testable import Claudio

/// Le tampon de flux est ce qui empêche la fenêtre d'avancer par à-coups sur
/// les réponses longues. S'il retenait un fragment de trop, du texte
/// disparaîtrait de l'écran — et personne ne le verrait en relisant le code.
@MainActor
final class StreamBufferTests: XCTestCase {

    private func session() -> CorrectionSession {
        CorrectionSession(action: .correct)
    }

    func testOuvrirUnFluxRepartDUnePageBlanche() {
        let session = session()
        session.correctedText = "d'avant"
        session.truncated = true
        session.justCopied = true

        session.beginStreaming()

        XCTAssertEqual(session.correctedText, "")
        XCTAssertFalse(session.truncated)
        XCTAssertFalse(session.justCopied)
        XCTAssertEqual(session.phase, .streaming)
    }

    /// Le premier fragment ne doit pas attendre : c'est lui qui dit à
    /// l'utilisateur que ça répond.
    func testLePremierFragmentSAfficheImmediatement() {
        let session = session()
        session.beginStreaming()

        session.appendStreamed("Bon")
        XCTAssertEqual(session.correctedText, "Bon")
    }

    /// Les suivants attendent le vidage, puis arrivent dans l'ordre et en une
    /// seule fois.
    func testLesFragmentsSuivantsAttendentLeVidage() {
        let session = session()
        session.beginStreaming()
        session.appendStreamed("Bon")

        session.appendStreamed("jour")
        session.appendStreamed(" tout")
        session.appendStreamed(" le monde")
        XCTAssertEqual(session.correctedText, "Bon")

        session.flushStreamed()
        XCTAssertEqual(session.correctedText, "Bonjour tout le monde")
    }

    func testViderUnTamponVideNeChangeRien() {
        let session = session()
        session.beginStreaming()
        session.appendStreamed("Bonjour")

        session.flushStreamed()
        session.flushStreamed()
        XCTAssertEqual(session.correctedText, "Bonjour")
    }

    /// La fin du flux fait foi : elle remplace le texte publié en route, et ce
    /// qui restait en tampon part avec lui.
    func testLaFinDuFluxRemplaceToutEtNeLaisseRienDerriere() {
        let session = session()
        session.beginStreaming()
        session.appendStreamed("Bon")
        session.appendStreamed("jou")  // reste en tampon

        session.finishStreaming(with: "Bonjour tout le monde", truncated: true)
        XCTAssertEqual(session.correctedText, "Bonjour tout le monde")
        XCTAssertTrue(session.truncated)
        XCTAssertEqual(session.phase, .done)

        // Le tampon a été vidé, pas seulement ignoré : un vidage tardif ne doit
        // pas venir recoller un morceau à la fin du texte final.
        session.flushStreamed()
        XCTAssertEqual(session.correctedText, "Bonjour tout le monde")
    }

    /// ⏎ pendant le flux ne doit pas coller un résultat à moitié écrit.
    func testOnNeCollePasAvantLaFinDuFlux() {
        let session = session()
        session.beginStreaming()
        session.appendStreamed("Bonjour")
        XCTAssertFalse(session.canPaste)

        session.finishStreaming(with: "Bonjour", truncated: false)
        XCTAssertTrue(session.canPaste)

        // Un résultat vide n'a rien à coller, même « terminé ».
        session.finishStreaming(with: "", truncated: false)
        XCTAssertFalse(session.canPaste)
    }

    /// Un flux qui repart (« Réessayer + ») ne doit pas hériter du tampon du
    /// précédent.
    func testUnNouveauFluxNeRecolleRienDuPrecedent() {
        let session = session()
        session.beginStreaming()
        session.appendStreamed("Premier")
        session.appendStreamed(" essai")

        session.beginStreaming()
        session.flushStreamed()
        XCTAssertEqual(session.correctedText, "")

        session.appendStreamed("Second")
        XCTAssertEqual(session.correctedText, "Second")
    }
}
