import XCTest
@testable import Claudio

/// A cleanup keeps the speaker's words; an answer to the dictation doesn't.
/// The two answers Haiku gave on 2026-10-03 are kept here as they came back.
final class CleanupPlausibilityTests: XCTestCase {

    func testTheTwoAnswersOfOctoberThirdAreNotCleanups() {
        XCTAssertFalse(CleanupPlausibility.isCleanup(
            "Je comprends. Je suis prêt à nettoyer ta transcription vocale selon la méthode décrite : ponctuation, majuscules, suppression des hésitations et répétitions, application des autocorrections du locuteur, sans reformulation ni ajout.\n\nEnvoie-moi le texte à mettre au propre.",
            of: "Voici mon message, laisse tomber la liste. C'est une erreur de ma part. Je veux bien que tu fasses la correction que tu proposes"))
        XCTAssertFalse(CleanupPlausibility.isCleanup(
            "J'ai bien compris. Je suis prêt à nettoyer les transcriptions vocales selon les règles que tu as énoncées :\n\n- Ponctuation et majuscules\n- Suppression des hésitations et tics d'oralité\n\nJe suis prêt à recevoir les transcriptions à nettoyer.",
            of: "pour la liste c'est une erreur. Oui je veux bien que tu fasses là justement que tu proposes"))
    }

    /// Real cleanups from the same evening's history: punctuation, a figure
    /// written out, a name from the vocabulary, hesitations gone.
    func testRealCleanupsPass() {
        XCTAssertTrue(CleanupPlausibility.isCleanup(
            "J'ai encore régulièrement des problèmes avec Haïku 4.5, notamment qui ne comprend pas qu'il doit rester silencieux.",
            of: "J'ai encore régulièrement des problèmes avec Haïku quatre point cinq, notamment qui ne comprend pas qu'il doit rester silencieux."))
        XCTAssertTrue(CleanupPlausibility.isCleanup(
            "J'avais pas vu, mais on a eu un nouveau client Twilee cet après-midi qui a payé direct un an pour 159 €. C'est pas la richesse, mais ça fait plaisir.",
            of: "J'avais pas vu, mais on a eu un nouveau client Twilly cet après-midi qui a payé direct un an pour 159 € c'est pas la richesse mais ça fait plaisir."))
        XCTAssertTrue(CleanupPlausibility.isCleanup(
            "On se voit mercredi à 14 h.",
            of: "euh on se voit mardi non mercredi à quatorze heures"))
    }

    /// Figures said in words come back as digits, which were never "said":
    /// a dictation that is mostly numbers is still a cleanup.
    func testFiguresWrittenAsDigitsCountAsSaid() {
        XCTAssertTrue(CleanupPlausibility.isCleanup(
            "Les chiffres sont 345, 12, 8, 14 et 32.",
            of: "les chiffres sont trois cent quarante-cinq, douze, huit, quatorze et trente-deux"))
    }

    /// Too short to judge: "trois" becoming "3" is a cleanup.
    func testAShortAnswerIsNeverJudged() {
        XCTAssertTrue(CleanupPlausibility.isCleanup("3", of: "trois"))
    }

    func testWordsFoldCaseAndAccents() {
        XCTAssertEqual(CleanupPlausibility.words(in: "C'est l'Été !"), ["c", "est", "l", "ete"])
    }
}
