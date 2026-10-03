import SwiftUI

@MainActor
struct GeneralPane: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var costCounterEnabled = AppSettings.costCounterEnabled()
    @State private var panelTextSize = AppSettings.panelTextSize
    @State private var language = AppSettings.language
    @ObservedObject private var ledger = CostLedger.shared
    @ObservedObject private var catalog = ModelCatalog.shared

    var body: some View {
        Form {
            Section(loc("Système", en: "System")) {
                Toggle(loc("Ouvrir à l'ouverture de session", en: "Open at login"),
                       isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.orange)
                }
            }

            Section(loc("Langue", en: "Language")) {
                Picker(loc("Langue de l'interface", en: "Interface language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .onChange(of: language) { AppSettings.language = language }
                Text(loc("S'applique aux libellés de Claudio. Le texte que Claude renvoie, lui, reste toujours dans la langue du texte sélectionné, ou dans celle de ta demande quand rien n'est sélectionné.",
                         en: "Applies to Claudio's own labels. What Claude sends back always follows the language of the selected text, or of your request when nothing is selected."))
                    .settingsNote()
            }

            Section(loc("Panneau", en: "Panel")) {
                Picker(loc("Taille du texte", en: "Text size"), selection: $panelTextSize) {
                    ForEach(PanelTextSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .onChange(of: panelTextSize) { AppSettings.panelTextSize = panelTextSize }
                Text(loc("Le résultat s'affiche à cette taille.", en: "The result appears at this size."))
                    .font(.system(size: panelTextSize.bodyPoints))
                    .foregroundStyle(.secondary)
                Text(loc("S'applique au texte du panneau flottant : le résultat, la consigne et les actions de la palette. Le panneau s'élargit avec le texte, et le changement vaut pour le panneau suivant.",
                         en: "Applies to the floating panel: the result, the instruction field and the palette actions. The panel widens with the text, and the change takes effect on the next panel."))
                    .settingsNote()
            }

            Section(loc("Modèle", en: "Model")) {
                LabeledContent(loc("Modèle", en: "Model"),
                               value: loc("réglable par raccourci", en: "set per shortcut"))
                Text(loc("Le modèle se choisit pour chaque raccourci dans l'onglet Modèles : un modèle Claude, ou un modèle local servi par Ollama. Tarifs Anthropic par million de jetons, entrée / sortie : \(catalog.models.compactMap(\.priceLine).joined(separator: ", ")). Le local est gratuit et ne sort pas de ta machine.",
                         en: "The model is chosen per shortcut in the Models tab: a Claude model, or a local model served by Ollama. Anthropic prices per million tokens, input / output: \(catalog.models.compactMap(\.priceLine).joined(separator: ", ")). Local models are free and never leave your Mac."))
                    .settingsNote()
            }

            Section(loc("Dépense", en: "Spending")) {
                Toggle(loc("Compter ce que je dépense", en: "Count what I spend"), isOn: $costCounterEnabled)
                    .onChange(of: costCounterEnabled) {
                        AppSettings.setCostCounterEnabled(costCounterEnabled)
                    }
                if costCounterEnabled {
                    LabeledContent(loc("Aujourd'hui", en: "Today")) {
                        Text(ledger.day.actions == 0
                             ? loc("aucune action", en: "no action yet")
                             : "\(ledger.day.formattedTotal) · \(ledger.day.actions) action\(ledger.day.actions > 1 ? "s" : "")")
                            .monospacedDigit()
                    }
                    Button(loc("Remettre à zéro", en: "Reset")) { ledger.reset() }
                        .disabled(ledger.day.actions == 0)
                }
                Text(loc("Le total est calculé sur ta machine à partir des jetons facturés par appel, et repart à zéro chaque jour. Le décompte qui fait foi reste celui de console.anthropic.com.",
                         en: "The total is computed on your Mac from the tokens billed per call, and starts over every day. The count that matters is still the one on console.anthropic.com."))
                    .settingsNote()
                if costCounterEnabled, ledger.day.unpricedActions > 0 {
                    Text(loc("* \(ledger.day.unpricedActions) appel\(ledger.day.unpricedActions > 1 ? "s" : "") à un modèle dont cette version de Claudio ne connaît pas le tarif : compté\(ledger.day.unpricedActions > 1 ? "s" : "") pour zéro, le total est un plancher.",
                             en: "* \(ledger.day.unpricedActions) call\(ledger.day.unpricedActions > 1 ? "s" : "") to a model whose price this version of Claudio doesn't know, counted as zero: the total is a floor."))
                        .settingsNote()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { ledger.refresh() }
    }

    /// The switch, flipped by hand, and only that: putting it back after a
    /// failure goes through no setter, so the reason stays on screen rather
    /// than being cleared by a second, needless try.
    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = loc("Nécessite l'app installée dans /Applications (\(error.localizedDescription))",
                                 en: "Requires the app to live in /Applications (\(error.localizedDescription))")
            launchAtLogin = LoginItem.isEnabled
        }
    }
}
