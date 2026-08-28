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
        alert.messageText = "Autorisation Accessibilité requise"
        alert.informativeText = """
        Plume a besoin de l'autorisation « Accessibilité » pour lire la sélection \
        et coller le texte corrigé.

        Réglages Système → Confidentialité et sécurité → Accessibilité → activer Plume, \
        puis relance le raccourci.
        """
        alert.addButton(withTitle: "Ouvrir les Réglages Système")
        alert.addButton(withTitle: "Plus tard")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
