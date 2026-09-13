import AVFoundation
import Speech
import XCTest
@testable import Claudio

/// The only part of `MicrophonePermission` that can be tested: the mapping
/// from the two system statuses to the error the panel shows. Everything
/// else asks macOS a question a test has no business asking.
final class MicrophonePermissionTests: XCTestCase {

    /// The microphone is asked for first: speech recognition without sound
    /// to give it would be an authorization requested for nothing.
    func testAMissingMicrophoneWinsOverEverythingElse() {
        for microphone in [AVAuthorizationStatus.notDetermined, .denied, .restricted] {
            for recognition in [SFSpeechRecognizerAuthorizationStatus.notDetermined,
                                .denied, .restricted, .authorized] {
                let missing = MicrophonePermission.missingAccess(microphone: microphone,
                                                                 recognition: recognition)
                guard case .microphoneDenied = missing else {
                    return XCTFail("micro \(microphone.rawValue) / reco \(recognition.rawValue)")
                }
            }
        }
    }

    /// Microphone granted, recognition not: the second pane is the one to
    /// send the user to, so the two errors must not be confused.
    func testAMissingRecognitionIsItsOwnError() {
        for recognition in [SFSpeechRecognizerAuthorizationStatus.notDetermined, .denied, .restricted] {
            let missing = MicrophonePermission.missingAccess(microphone: .authorized,
                                                             recognition: recognition)
            guard case .recognitionDenied = missing else {
                return XCTFail("reco \(recognition.rawValue)")
            }
        }
    }

    func testBothGrantedMeansNothingIsMissing() {
        XCTAssertNil(MicrophonePermission.missingAccess(microphone: .authorized, recognition: .authorized))
    }

    /// Each error says where to go: a message that names no pane sends the
    /// user nowhere.
    func testEachErrorNamesItsSettingsPane() {
        let previous = AppSettings.language
        defer { AppSettings.language = previous }
        AppSettings.language = .french
        XCTAssertTrue(SpeechEngineError.microphoneDenied.errorDescription?.contains("Microphone") == true)
        XCTAssertTrue(SpeechEngineError.recognitionDenied.errorDescription?.contains("Reconnaissance vocale") == true)
        AppSettings.language = .english
        XCTAssertTrue(SpeechEngineError.microphoneDenied.errorDescription?.contains("Microphone") == true)
        XCTAssertTrue(SpeechEngineError.recognitionDenied.errorDescription?.contains("Speech Recognition") == true)
    }

    /// A language that isn't installed is the one failure the panel can offer
    /// a way out of, so it — and only it — carries the pane to open. The two
    /// refusals come with their own alert, which opens its own pane.
    func testOnlyAMissingLanguageCarriesAPaneToOpen() {
        let missing = SpeechEngineError.languageUnavailable(Locale(identifier: "fr-FR"))
        XCTAssertEqual(missing.settingsURL?.absoluteString,
                       "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        XCTAssertNil(SpeechEngineError.microphoneDenied.settingsURL)
        XCTAssertNil(SpeechEngineError.recognitionDenied.settingsURL)
        XCTAssertNil(SpeechEngineError.audioEngine("boom").settingsURL)
        XCTAssertNil(SpeechEngineError.recognizer("boom").settingsURL)
    }
}
