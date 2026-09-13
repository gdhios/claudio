import AVFoundation
import AppKit
import Speech

/// The two permissions dictation needs: the microphone, and speech
/// recognition. Modelled on `AccessibilityPermission` — read the state, ask
/// for it, explain it — so the coordinator treats all three permissions the
/// same way.
/// The two permissions as the dictation cycle needs them: read, ask,
/// explain. Injected as one value, like `PasteService`, so a test can run a
/// whole cycle without TCC — and so a preview never asks anything.
@MainActor
struct MicrophoneGate {
    var isGranted: @MainActor () -> Bool
    var request: @MainActor () async -> Bool
    var showExplanation: @MainActor () -> Void

    static let system = MicrophoneGate(isGranted: { MicrophonePermission.isGranted },
                                       request: MicrophonePermission.request,
                                       showExplanation: MicrophonePermission.showExplanation)
}

@MainActor
enum MicrophonePermission {
    static var isGranted: Bool { missingAccess() == nil }

    /// What is missing, if anything. Pure on purpose: the two statuses come
    /// in, the error the panel shows comes out. It is the only part of this
    /// file a test can reach, and the engine reports exactly the same thing.
    ///
    /// The microphone comes first: speech recognition without sound to give
    /// it would be an authorization asked for nothing.
    nonisolated static func missingAccess(
        microphone: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio),
        recognition: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    ) -> SpeechEngineError? {
        guard microphone == .authorized else { return .microphoneDenied }
        guard recognition == .authorized else { return .recognitionDenied }
        return nil
    }

    /// Triggers the two system prompts, in that order, and answers only once
    /// both are granted. Each one is asked for only if it is still missing:
    /// a denied permission never prompts again, it sends you to Settings.
    static func request() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { return false }
        }
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard status == .authorized else { return false }
        }
        return true
    }

    /// Explains what is missing and opens the right pane. Two panes, because
    /// macOS lists the microphone and speech recognition separately: sending
    /// someone to the wrong one is sending them nowhere.
    static func showExplanation() {
        guard let missing = missingAccess() else { return }
        let pane: String
        let alert = NSAlert()
        switch missing {
        case .recognitionDenied:
            pane = "Privacy_SpeechRecognition"
            alert.messageText = loc("Autorisation Reconnaissance vocale requise",
                                    en: "Speech Recognition permission needed")
            alert.informativeText = loc("""
            Claudio a besoin de l'autorisation « Reconnaissance vocale » pour transformer \
            ta voix en texte, sur cet ordinateur.

            Réglages Système → Confidentialité et sécurité → Reconnaissance vocale → \
            activer Claudio, puis relance le raccourci.
            """, en: """
            Claudio needs the “Speech Recognition” permission to turn your voice into \
            text, on this Mac.

            System Settings → Privacy & Security → Speech Recognition → turn Claudio on, \
            then trigger the shortcut again.
            """)
        default:
            pane = "Privacy_Microphone"
            alert.messageText = loc("Autorisation Microphone requise",
                                    en: "Microphone permission needed")
            alert.informativeText = loc("""
            Claudio a besoin de l'autorisation « Microphone » pour t'entendre dicter.

            Réglages Système → Confidentialité et sécurité → Microphone → activer Claudio, \
            puis relance le raccourci.
            """, en: """
            Claudio needs the “Microphone” permission to hear you dictate.

            System Settings → Privacy & Security → Microphone → turn Claudio on, \
            then trigger the shortcut again.
            """)
        }
        alert.addButton(withTitle: loc("Ouvrir les Réglages Système", en: "Open System Settings"))
        alert.addButton(withTitle: loc("Plus tard", en: "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
            NSWorkspace.shared.open(url)
        }
    }
}
