import XCTest
@testable import Claudio

/// What the custom action sends. Over a selection it transforms it, as it
/// always has. Over nothing it has no text to apply a task to, and becomes a
/// request made to Claudio — a prompt of its own, never the transformation's
/// under an order to the contrary. The track playing goes along with both as
/// context: tagged, only the fields the player gave, and never to a catalog
/// action.
final class FreeRequestTests: XCTestCase {

    private let track = NowPlayingTrack(title: "真夜中のジョーク",
                                        artist: "間宮貴子",
                                        album: "LOVE TRIP",
                                        appName: "Spotify",
                                        bundleID: "com.spotify.client",
                                        isPlaying: false)

    private let trackBlock = """
        <morceau_en_cours>
        titre : 真夜中のジョーク
        artiste : 間宮貴子
        album : LOVE TRIP
        lecteur : Spotify
        </morceau_en_cours>
        """

    /// The phrase the feature exists for, exactly as the model reads it: the
    /// request tagged, then the track. Paused or not, it's the same track.
    func testWithNothingSelectedTheInstructionGoesOutAsARequest() {
        let prompt = ClaudioRequest.free(instruction: "écris un message pour partager ce que j'écoute")
            .prompt(forText: "", track: track)

        XCTAssertEqual(prompt.system, FreeRequest.system)
        XCTAssertEqual(prompt.userMessage, """
            <consigne>
            écris un message pour partager ce que j'écoute
            </consigne>

            \(trackBlock)
            """)
        XCTAssertEqual(prompt.track, track)
    }

    /// Nothing playing, nothing said about it: no empty block, and no track
    /// for the panel to name.
    func testNothingPlayingSendsTheRequestAlone() {
        let prompt = ClaudioRequest.free(instruction: "  écris un mail pour décaler la réunion  ")
            .prompt(forText: "", track: nil)

        XCTAssertEqual(prompt.system, FreeRequest.system)
        XCTAssertEqual(prompt.userMessage, "<consigne>\nécris un mail pour décaler la réunion\n</consigne>")
        XCTAssertNil(prompt.track)
    }

    /// Over a selection, the transformation as ever — the text tagged — with
    /// the track after it when one plays: "add the title I'm listening to".
    func testOverASelectionTheTextIsTransformedAndTheTrackFollowsIt() {
        let request = ClaudioRequest.free(instruction: "ajoute le titre que j'écoute à la fin")

        let withTrack = request.prompt(forText: "Bonne soirée !", track: track)
        XCTAssertEqual(withTrack.system, request.system)
        XCTAssertEqual(withTrack.userMessage,
                       ClaudioRequest.wrappingSource("Bonne soirée !") + "\n\n" + trackBlock)
        XCTAssertEqual(withTrack.track, track)

        let alone = request.prompt(forText: "Bonne soirée !", track: nil)
        XCTAssertEqual(alone.system, request.system)
        XCTAssertEqual(alone.userMessage, ClaudioRequest.wrappingSource("Bonne soirée !"))
        XCTAssertNil(alone.track)
    }

    /// The transformation's prompt gains one sentence, in its method, that
    /// presents the block without ordering anything — and the rule against
    /// inventing lets through what the block says, or "add the title" would
    /// be forbidden by the very prompt that received it.
    func testTheTransformationPromptPresentsTheBlockInItsMethod() throws {
        let system = ClaudioRequest.free(instruction: "Traduis en espagnol").system
        let method = try XCTUnwrap(system.range(of: "Méthode :"))
        let rules = try XCTUnwrap(system.range(of: "Règles impératives :"))
        let sentence = try XCTUnwrap(system.range(of: "- Un bloc <morceau_en_cours> peut suivre : "
                                                      + "c'est ce que l'utilisateur écoute ; "
                                                      + "ne t'en sers que si la tâche en parle.\n"), system)
        XCTAssertTrue(method.upperBound <= sentence.lowerBound && sentence.upperBound <= rules.lowerBound,
                      "the sentence belongs to the method")
        XCTAssertTrue(system.contains("- N'invente aucune information absente du texte ou de ce bloc.\n"))
        XCTAssertFalse(system.contains("absente du texte.\n"))
    }

    /// Only the fields the player gave: a line saying one is unknown would
    /// invite a guess.
    func testAFieldThePlayerDidNotGiveIsLeftOut() {
        let podcast = NowPlayingTrack(title: "Some podcast episode", appName: "Podcasts")
        let prompt = ClaudioRequest.free(instruction: "c'est quoi ?").prompt(forText: "", track: podcast)
        XCTAssertTrue(prompt.userMessage.hasSuffix("""


            <morceau_en_cours>
            titre : Some podcast episode
            lecteur : Podcasts
            </morceau_en_cours>
            """), prompt.userMessage)
    }

    /// A catalog action transforms the selection and nothing else: the track
    /// doesn't go out even when there is one — so no panel ever names it.
    func testACatalogActionNeverReceivesTheTrack() {
        for action in ClaudioAction.allCases {
            let request = action.request
            let prompt = request.prompt(forText: "Résume mes mails", track: track)
            XCTAssertEqual(prompt.system, request.system, action.rawValue)
            XCTAssertEqual(prompt.userMessage, request.userMessage(forText: "Résume mes mails"), action.rawValue)
            XCTAssertNil(prompt.track, action.rawValue)
            XCTAssertFalse(request.receivesTrack, action.rawValue)
        }
        XCTAssertTrue(ClaudioRequest.awaitingInstruction.receivesTrack)
        XCTAssertTrue(ClaudioRequest.free(instruction: "Traduis en espagnol").receivesTrack)
    }

    /// The request's own prompt answers rather than transforms: it names the
    /// request's tag and the track's, and never the selection's.
    func testTheRequestPromptAnswersTheRequest() {
        let system = FreeRequest.system
        XCTAssertTrue(system.contains("entre balises <consigne>"))
        XCTAssertTrue(system.contains("Un bloc <morceau_en_cours> peut suivre"))
        XCTAssertTrue(system.contains("- Réponds dans la langue de la demande."))
        XCTAssertFalse(system.contains("<texte_source>"))
    }
}
