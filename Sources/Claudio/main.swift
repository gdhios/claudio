import AppKit

// Command-line self-test mode: `Claudio --selftest [text] [instruction]`
// (uses the ANTHROPIC_API_KEY env var or Keychain key, no UI).
if CommandLine.arguments.contains("--selftest") {
    SelfTest.runBlocking()
    exit(0)
}

// UI preview mode (dev): `Claudio --preview <mode>`, the modes listed in
// Support/PreviewMode.swift.
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
