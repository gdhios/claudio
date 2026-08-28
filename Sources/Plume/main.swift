import AppKit

// Mode auto-test en ligne de commande : `Plume --selftest [texte]`
// (utilise la clé de l'env ANTHROPIC_API_KEY ou du Trousseau, aucune UI).
if CommandLine.arguments.contains("--selftest") {
    SelfTest.runBlocking()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
