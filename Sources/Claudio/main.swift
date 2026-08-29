import AppKit

// Mode auto-test en ligne de commande : `Claudio --selftest [texte]`
// (utilise la clé de l'env ANTHROPIC_API_KEY ou du Trousseau, aucune UI).
if CommandLine.arguments.contains("--selftest") {
    SelfTest.runBlocking()
    exit(0)
}

// Mode aperçu UI (dev) : `Claudio --preview <panel|panel-streaming|panel-long|panel-error|panel-noselection|settings>`
if let previewIndex = CommandLine.arguments.firstIndex(of: "--preview") {
    let mode = CommandLine.arguments.count > previewIndex + 1
        ? CommandLine.arguments[previewIndex + 1] : "panel"
    let previewApp = NSApplication.shared
    let previewDelegate = PreviewDelegate(mode: mode)
    previewApp.delegate = previewDelegate
    previewApp.setActivationPolicy(.accessory)
    previewApp.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
