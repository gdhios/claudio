import KeyboardShortcuts
import SwiftUI

@MainActor
struct ShortcutsPane: View {
    /// Where the dictation rows start, for the preview that scrolls to them.
    private static let dictationRows = "dictationRows"

    @State private var windowShortcutsEnabled = AppSettings.windowShortcutsEnabled
    @State private var dictationEnabled = AppSettings.dictationEnabled()

    var body: some View {
        ScrollViewReader { proxy in
            form
                .onAppear {
                    // The dictation rows sit below the fold of a preview's
                    // window, and nothing scrolls a preview but itself.
                    guard !PreviewRun.dictationLoneKeys.isEmpty else { return }
                    DispatchQueue.main.async { proxy.scrollTo(Self.dictationRows, anchor: .center) }
                }
        }
    }

    private var form: some View {
        Form {
            Section {
                // At the top: the palette, which gives access to everything else.
                ShortcutRow(symbol: PaletteCatalog.symbolName, tint: PaletteCatalog.tint,
                            title: PaletteCatalog.menuTitle) {
                    KeyboardShortcuts.Recorder("", name: .actionPalette)
                }
                ForEach(ClaudioAction.allCases, id: \.self) { action in
                    ShortcutRow(symbol: action.symbolName, tint: action.tint, title: action.menuTitle) {
                        KeyboardShortcuts.Recorder("", name: action.shortcutName)
                    }
                }
                // Outside the catalog: its instruction is entered in the panel.
                ShortcutRow(symbol: ClaudioRequest.awaitingInstruction.origin.symbolName,
                            tint: ClaudioRequest.awaitingInstruction.origin.tint,
                            title: ClaudioRequest.freeMenuTitle) {
                    KeyboardShortcuts.Recorder("", name: .freeAction)
                }
                // Outside the catalog too, and needs no selection at all.
                ShortcutRow(symbol: ListeningSession.symbolName, tint: ListeningSession.tint,
                            title: ListeningSession.menuTitle) {
                    KeyboardShortcuts.Recorder("", name: .whatsPlaying)
                }
            } header: {
                Text(loc("Raccourcis globaux", en: "Global shortcuts"))
            } footer: {
                Text(loc("Chaque action s'applique au texte sélectionné, dans n'importe quelle app. La palette les propose toutes dans le panneau, sans raccourci à retenir. L'action libre demande la consigne au moment du déclenchement : tapé, son raccourci ouvre le champ où l'écrire ; maintenu, il ouvre le micro pour la dire. Sans sélection, elle devient une demande à Claudio, et Entrée colle sa réponse au curseur. Avec ou sans sélection, elle emporte le morceau en cours s'il y en a un, même en pause ; les autres actions, jamais. « Qu'est-ce que j'écoute ? » se passe aussi de sélection : Claudio lit le morceau en cours et Claude te le présente.",
                         en: "Every action applies to the selected text, in any app. The palette offers all of them in the panel, with no shortcut to remember. The custom action asks for its instruction when you trigger it: tap its shortcut to type it, hold it to say it. With nothing selected, it becomes a request to Claudio, and Enter pastes the answer at the cursor. Selection or not, it takes the current track along if there is one, even paused; the other actions never do. “What's playing?” needs no selection either: Claudio reads the track playing and Claude tells you about it."))
                    .settingsNote()
            }

            Section {
                Toggle(loc("Activer la dictée", en: "Enable dictation"),
                       isOn: $dictationEnabled)
                    .onChange(of: dictationEnabled) {
                        HotkeySetup.setDictationEnabled(dictationEnabled)
                    }
                ShortcutRow(symbol: SettingsSection.dictation.symbolName,
                            tint: SettingsSection.dictation.color,
                            title: loc("Dicter", en: "Dictate")) {
                    // A key combination, or a right-hand modifier held alone.
                    DictationShortcutField(shortcut: .dictate)
                }
                .id(Self.dictationRows)
                .disabled(!dictationEnabled)
                ShortcutRow(symbol: "globe", tint: SettingsSection.dictation.color,
                            title: loc("Dicter dans l'autre langue", en: "Dictate in the other language")) {
                    DictationShortcutField(shortcut: .dictateOtherLanguage)
                }
                .disabled(!dictationEnabled)
            } header: {
                Text(SettingsSection.dictation.title)
            } footer: {
                Text(loc("Maintenus, ces deux-là écoutent tant que la touche est enfoncée et collent au relâchement ; tapés une fois, ils écoutent jusqu'au prochain appui. Une touche de modification seule, côté droit (⌥, ⌘, ⇧ ou ⌃), marche aussi : clique le champ, appuie sur la touche et relâche-la. Les langues et le modèle de nettoyage se règlent dans l'onglet Dictée. Décochée, la dictée rend les deux touches à tes autres outils.",
                         en: "Held, these two listen while the key is down and paste on release; tapped once, they listen until the next press. A modifier key on its own, right-hand side (⌥, ⌘, ⇧ or ⌃), works too: click the field, press the key and let go. The languages and the cleanup model are set in the Dictation tab. Switched off, dictation releases both keys and leaves them to your other tools."))
                    .settingsNote()
            }

            Section {
                Toggle(loc("Placer les fenêtres au clavier", en: "Move windows from the keyboard"),
                       isOn: $windowShortcutsEnabled)
                    .onChange(of: windowShortcutsEnabled) {
                        HotkeySetup.setWindowShortcutsEnabled(windowShortcutsEnabled)
                    }
                ForEach(WindowLayout.allCases, id: \.self) { layout in
                    ShortcutRow(symbol: layout.symbolName, tint: .indigo, title: layout.title) {
                        KeyboardShortcuts.Recorder("", name: layout.shortcutName)
                    }
                    .disabled(!windowShortcutsEnabled)
                }
                // Not a layout: this one keeps the placement and changes display.
                ShortcutRow(symbol: "display.2", tint: .indigo, title: loc("Écran suivant", en: "Next display")) {
                    KeyboardShortcuts.Recorder("", name: .windowNextScreen)
                }
                .disabled(!windowShortcutsEnabled)
            } header: {
                Text(loc("Fenêtres", en: "Windows"))
            } footer: {
                Text(loc("Cale la fenêtre du premier plan sur ⌃⌥⌘ : flèches pour les moitiés, ↩ pour maximiser, 7/9/1/3 pour les coins, 5 pour centrer et ⇟ pour l'envoyer sur l'écran suivant en gardant sa place. Si un autre outil (Raycast, Rectangle…) tient déjà ces touches, coupe-le sur celles-ci ou change les raccourcis ici.",
                         en: "Snaps the frontmost window on ⌃⌥⌘: arrows for halves, ↩ to maximize, 7/9/1/3 for the corners, 5 to center and ⇟ to send it to the next display, keeping its placement. If another tool (Raycast, Rectangle…) already owns these keys, disable it on them or change the shortcuts here."))
                    .settingsNote()
            }
        }
        .formStyle(.grouped)
    }
}

/// A shortcut's row: its icon, its name, and the field that records it.
private struct ShortcutRow<Field: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    @ViewBuilder let field: Field

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(systemName: symbol, color: tint, size: 22)
            Text(title)
            Spacer()
            field
        }
    }
}
