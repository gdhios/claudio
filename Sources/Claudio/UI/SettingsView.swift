import SwiftUI
import KeyboardShortcuts

/// Réglages façon Réglages Système : barre latérale à pastilles colorées,
/// sections en cartes (`.formStyle(.grouped)`).
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case apiKey
    case shortcuts
    case prompts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: loc("Général", en: "General")
        case .apiKey: loc("Clé API", en: "API key")
        case .shortcuts: loc("Raccourcis", en: "Shortcuts")
        case .prompts: loc("Prompts", en: "Prompts")
        case .about: loc("À propos", en: "About")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape.fill"
        case .apiKey: "key.fill"
        case .shortcuts: "command"
        case .prompts: "text.quote"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .apiKey: ClaudioTheme.accent
        case .shortcuts: .indigo
        case .prompts: .orange
        case .about: .blue
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsSection?

    init(initialSection: SettingsSection = .general) {
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label {
                    Text(section.title)
                } icon: {
                    IconBadge(systemName: section.symbolName, color: section.color)
                }
                .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 220)
        } detail: {
            switch selection ?? .general {
            case .general: GeneralPane().navigationTitle(SettingsSection.general.title)
            case .apiKey: APIKeyPane().navigationTitle(SettingsSection.apiKey.title)
            case .shortcuts: ShortcutsPane().navigationTitle(SettingsSection.shortcuts.title)
            case .prompts: PromptsPane().navigationTitle(SettingsSection.prompts.title)
            case .about: AboutPane().navigationTitle(SettingsSection.about.title)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - Général

@MainActor
private struct GeneralPane: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var costCounterEnabled = AppSettings.costCounterEnabled
    @State private var panelTextSize = AppSettings.panelTextSize
    @State private var language = AppSettings.language
    @ObservedObject private var ledger = CostLedger.shared

    var body: some View {
        Form {
            Section(loc("Système", en: "System")) {
                Toggle(loc("Ouvrir à l'ouverture de session", en: "Open at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do {
                            try LoginItem.setEnabled(launchAtLogin)
                            loginItemError = nil
                        } catch {
                            loginItemError = loc("Nécessite l'app installée dans /Applications (\(error.localizedDescription))",
                                                 en: "Requires the app to live in /Applications (\(error.localizedDescription))")
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
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
                Text(loc("S'applique aux libellés de Claudio. Le texte que Claude renvoie, lui, reste toujours dans la langue du texte sélectionné.",
                         en: "Applies to Claudio's own labels. What Claude sends back always follows the language of the selected text."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(loc("Modèle", en: "Model")) {
                LabeledContent(loc("Modèle Claude", en: "Claude model"),
                               value: loc("réglable par action", en: "set per action"))
                Text(loc("Le modèle se choisit pour chaque action dans l'onglet Prompts. Tarifs Anthropic par million de jetons, entrée / sortie : \(ClaudioModel.allCases.map(\.priceLine).joined(separator: ", ")).",
                         en: "The model is chosen per action in the Prompts tab. Anthropic prices per million tokens, input / output: \(ClaudioModel.allCases.map(\.priceLine).joined(separator: ", "))."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(loc("Dépense", en: "Spending")) {
                Toggle(loc("Compter ce que je dépense", en: "Count what I spend"), isOn: $costCounterEnabled)
                    .onChange(of: costCounterEnabled) {
                        AppSettings.costCounterEnabled = costCounterEnabled
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { ledger.refresh() }
    }
}

// MARK: - Clé API

private struct APIKeyPane: View {
    @State private var apiKeyField = ""
    @State private var hasStoredKey = KeychainStore.loadAPIKey() != nil
    @State private var workspaceIDField = AppSettings.workspaceID ?? ""

    var body: some View {
        Form {
            Section(loc("Clé API Anthropic", en: "Anthropic API key")) {
                SecureField("sk-ant-…", text: $apiKeyField)
                HStack {
                    if hasStoredKey {
                        Label(loc("Clé enregistrée dans le Trousseau", en: "Key saved in the Keychain"), systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Label(loc("Aucune clé enregistrée", en: "No key saved"), systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    Spacer()
                    if hasStoredKey {
                        Button(loc("Supprimer", en: "Delete")) {
                            KeychainStore.deleteAPIKey()
                            hasStoredKey = false
                        }
                    }
                    Button(loc("Enregistrer", en: "Save")) {
                        let trimmed = apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        KeychainStore.saveAPIKey(trimmed)
                        apiKeyField = ""
                        hasStoredKey = true
                    }
                    .disabled(apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Link(loc("Créer une clé sur console.anthropic.com", en: "Create a key on console.anthropic.com"),
                     destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
            }

            Section(loc("Espace de travail", en: "Workspace")) {
                TextField(loc("Espace de travail", en: "Workspace"), text: $workspaceIDField, prompt: Text("wrkspc_…"))
                    .onChange(of: workspaceIDField) {
                        AppSettings.workspaceID = workspaceIDField
                    }
                Text(loc("Requis uniquement si ta clé est « liée à l'identité » (erreur 400 sinon). Console → Réglages → Workspaces → copier l'ID de l'espace.",
                         en: "Only needed if your key is “identity-bound” (otherwise you get a 400). Console → Settings → Workspaces → copy the workspace ID."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Raccourcis

private struct ShortcutsPane: View {
    var body: some View {
        Form {
            Section {
                // En tête : la palette, qui donne accès à tout le reste.
                HStack(spacing: 10) {
                    IconBadge(systemName: PaletteCatalog.symbolName,
                              color: PaletteCatalog.tint, size: 22)
                    Text(PaletteCatalog.menuTitle)
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .actionPalette)
                }
                ForEach(ClaudioAction.allCases, id: \.self) { action in
                    HStack(spacing: 10) {
                        IconBadge(systemName: action.symbolName, color: action.tint, size: 22)
                        Text(action.menuTitle)
                        Spacer()
                        KeyboardShortcuts.Recorder("", name: action.shortcutName)
                    }
                }
                // Hors catalogue : sa consigne se saisit dans le panneau.
                HStack(spacing: 10) {
                    IconBadge(systemName: ClaudioRequest.awaitingInstruction.origin.symbolName,
                              color: ClaudioRequest.awaitingInstruction.origin.tint, size: 22)
                    Text(ClaudioRequest.freeMenuTitle)
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .freeAction)
                }
            } header: {
                Text(loc("Raccourcis globaux", en: "Global shortcuts"))
            } footer: {
                Text(loc("Chaque action s'applique au texte sélectionné, dans n'importe quelle app. La palette les propose toutes dans le panneau, sans raccourci à retenir. L'action libre demande la consigne à appliquer au moment du déclenchement.",
                         en: "Every action applies to the selected text, in any app. The palette offers all of them in the panel, with no shortcut to remember. The custom action asks for its instruction when you trigger it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Prompts

private struct PromptsPane: View {
    @State private var selectedAction: ClaudioAction = .correct
    @State private var promptText: String = ClaudioAction.correct.system
    @State private var selectedModel: ModelChoice = ClaudioAction.correct.model

    private var isCustomized: Bool { promptText != selectedAction.defaultSystem }

    var body: some View {
        Form {
            Section {
                Picker(loc("Action", en: "Action"), selection: $selectedAction) {
                    ForEach(ClaudioAction.allCases, id: \.self) { action in
                        Text(action.menuTitle).tag(action)
                    }
                }
                .onChange(of: selectedAction) {
                    promptText = selectedAction.system
                    selectedModel = selectedAction.model
                }
            }

            Section(loc("Modèle", en: "Model")) {
                Picker(loc("Modèle Claude", en: "Claude model"), selection: $selectedModel) {
                    ForEach(ClaudioModel.allCases, id: \.self) { model in
                        Text(model.displayName).tag(ModelChoice.claude(model))
                    }
                }
                .onChange(of: selectedModel) {
                    AppSettings.setCustomModel(selectedModel, for: selectedAction)
                }
                Text("\(selectedModel.costHint). \(selectedModel == .claude(selectedAction.defaultModel) ? loc("Modèle par défaut pour cette action.", en: "Default model for this action.") : loc("Modèle personnalisé, le défaut est \(selectedAction.defaultModel.displayName).", en: "Custom model; the default is \(selectedAction.defaultModel.displayName)."))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(loc("Prompt système", en: "System prompt")) {
                TextEditor(text: $promptText)
                    .font(.callout)
                    .frame(minHeight: 260)
                    .onChange(of: promptText) {
                        // Identique au défaut → on retire l'override (suit les mises à jour de l'app).
                        AppSettings.setCustomSystemPrompt(isCustomized ? promptText : nil,
                                                          for: selectedAction)
                    }
                HStack {
                    if isCustomized {
                        Label(loc("Personnalisé", en: "Customised"), systemImage: "pencil")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label(loc("Prompt par défaut", en: "Default prompt"), systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(loc("Réinitialiser", en: "Reset")) {
                        AppSettings.setCustomSystemPrompt(nil, for: selectedAction)
                        promptText = selectedAction.defaultSystem
                    }
                    .disabled(!isCustomized)
                }
                Text(loc("Modifications appliquées immédiatement. Le texte sélectionné est envoyé à part, balisé <texte_source> pour les actions de prompt : ce prompt ne définit que la tâche. Les prompts par défaut sont écrits en français, et demandent à Claude de répondre dans la langue du texte sélectionné.",
                         en: "Changes take effect immediately. The selected text is sent separately, wrapped in <texte_source> for the prompt actions: this prompt only defines the task. The default prompts are written in French, and ask Claude to answer in the language of the selected text."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - À propos

private struct AboutPane: View {
    @State private var checking = false
    @State private var installing = false
    @State private var updateMessage: String?
    @State private var pendingUpdate: UpdateChecker.Feed?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claudio").font(.title3.bold())
                        Text(loc("Version \(version)", en: "Version \(version)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(loc("Des actions IA sur votre texte sélectionné, partout sur macOS.",
                                 en: "AI actions on your selected text, anywhere on macOS."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(loc("Mises à jour", en: "Updates")) {
                HStack {
                    Button(loc("Vérifier maintenant", en: "Check now")) {
                        checking = true
                        Task { @MainActor in
                            switch await UpdateChecker.shared.checkNow() {
                            case .upToDate:
                                updateMessage = loc("Claudio est à jour (version \(version)).",
                                                    en: "Claudio is up to date (version \(version)).")
                                pendingUpdate = nil
                            case .updateAvailable(let feed):
                                updateMessage = loc("Mise à jour \(feed.version) disponible.",
                                                    en: "Update \(feed.version) available.")
                                pendingUpdate = feed
                            case .failed:
                                updateMessage = loc("Vérification impossible, réessayez plus tard.",
                                                    en: "Could not check, try again later.")
                                pendingUpdate = nil
                            }
                            checking = false
                        }
                    }
                    .disabled(checking || installing)
                    if checking || installing {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if let pendingUpdate {
                        Button(loc("Installer et redémarrer", en: "Install and restart")) { install(pendingUpdate) }
                            .disabled(installing)
                    }
                }
                if let updateMessage {
                    Text(updateMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text(loc("Vérification automatique une fois par jour : une simple lecture de version.json sur claudio.okonoma.com, aucune donnée envoyée. L'installation remplace l'app en place et relance Claudio, sans rien laisser dans les Téléchargements.",
                         en: "Checked automatically once a day: a plain read of version.json on claudio.okonoma.com, nothing sent. Installing replaces the app in place and relaunches Claudio, leaving nothing in Downloads."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link(destination: URL(string: "https://claudio.okonoma.com")!) {
                    Label(loc("Site web", en: "Website"), systemImage: "globe")
                }
                Link(destination: URL(string: "https://github.com/gdhios/claudio")!) {
                    Label(loc("Code source (MIT)", en: "Source code (MIT)"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://buymeacoffee.com/gdhios")!) {
                    Label(loc("Offrir un café ☕", en: "Buy me a coffee ☕"), systemImage: "heart")
                }
            }

            Section {
                Text(loc("Fait main en Swift. Projet indépendant, non affilié à Anthropic. Claude est une marque d'Anthropic, PBC.",
                         en: "Hand-made in Swift. Independent project, not affiliated with Anthropic. Claude is a trademark of Anthropic, PBC."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Télécharge, vérifie et installe : en cas de succès l'app se termine et
    /// la nouvelle version se relance seule.
    private func install(_ feed: UpdateChecker.Feed) {
        installing = true
        updateMessage = loc("Téléchargement de la version \(feed.version)…",
                            en: "Downloading version \(feed.version)…")
        Task { @MainActor in
            do {
                let newApp = try await UpdateInstaller.prepare(from: feed.url)
                try UpdateInstaller.installAndRelaunch(newApp)
            } catch {
                updateMessage = error.localizedDescription
                installing = false
            }
        }
    }
}
