import AppKit
import ApplicationServices

@MainActor
enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Déclenche la demande système (une seule fois par identité de signature).
    @discardableResult
    static func request() -> Bool {
        if AXIsProcessTrusted() { return true }
        // Valeur littérale de kAXTrustedCheckOptionPrompt (le global C n'est pas
        // Sendable sous Swift 6 strict).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func showExplanation() {
        let alert = NSAlert()
        alert.messageText = loc("Autorisation Accessibilité requise",
                                en: "Accessibility permission needed")
        alert.informativeText = loc("""
        Claudio a besoin de l'autorisation « Accessibilité » pour lire la sélection \
        et coller le texte corrigé.

        Réglages Système → Confidentialité et sécurité → Accessibilité → activer Claudio, \
        puis relance le raccourci.
        """, en: """
        Claudio needs the “Accessibility” permission to read your selection \
        and paste the result back.

        System Settings → Privacy & Security → Accessibility → turn Claudio on, \
        then trigger the shortcut again.
        """)
        alert.addButton(withTitle: loc("Ouvrir les Réglages Système", en: "Open System Settings"))
        alert.addButton(withTitle: loc("Plus tard", en: "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
