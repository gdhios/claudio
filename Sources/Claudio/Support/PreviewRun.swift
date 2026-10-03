/// True when the app is running in preview (`--preview <mode>`, the modes
/// `PreviewDelegate` knows and `Scripts/test.sh` renders). A view uses it to
/// avoid asking the network for anything: a preview must render the same
/// screen on every machine, including a CI runner where nothing is listening
/// (TESTING.md, level 2).
enum PreviewRun {
    static let isActive = CommandLine.arguments.contains("--preview")

    /// The lone keys a preview shows on the dictation shortcuts: none unless
    /// its mode sets one, and never this Mac's. A preview that sets one is
    /// about those rows, and scrolls down to them.
    @MainActor static var dictationLoneKeys: [DictationShortcut: LoneModifierKey] = [:]
}
