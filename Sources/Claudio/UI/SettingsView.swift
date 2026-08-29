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
        case .general: "Général"
        case .apiKey: "Clé API"
        case .shortcuts: "Raccourcis"
        case .prompts: "Prompts"
        case .about: "À propos"
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
            case .general: GeneralPane().navigationTitle("Général")
            case .apiKey: APIKeyPane().navigationTitle("Clé API")
            case .shortcuts: ShortcutsPane().navigationTitle("Raccourcis")
            case .prompts: PromptsPane().navigationTitle("Prompts")
            case .about: AboutPane().navigationTitle("À propos")
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - Général

private struct GeneralPane: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("Système") {
                Toggle("Ouvrir à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do {
                            try LoginItem.setEnabled(launchAtLogin)
                            loginItemError = nil
                        } catch {
                            loginItemError = "Nécessite l'app installée dans /Applications (\(error.localizedDescription))"
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Modèle") {
                LabeledContent("Modèle Claude", value: "réglable par action")
                Text("Le modèle se choisit pour chaque action dans l'onglet Prompts. Ordre de grandeur par action courte : ≈ 0,2 centime avec Haiku, ≈ 0,5 centime avec Sonnet, ≈ 1 centime avec Opus. La clé et la consommation se gèrent sur console.anthropic.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Clé API

private struct APIKeyPane: View {
    @State private var apiKeyField = ""
    @State private var hasStoredKey = KeychainStore.loadAPIKey() != nil
    @State private var workspaceIDField = AppSettings.workspaceID ?? ""

    var body: some View {
        Form {
            Section("Clé API Anthropic") {
                SecureField("sk-ant-…", text: $apiKeyField)
                HStack {
                    if hasStoredKey {
                        Label("Clé enregistrée dans le Trousseau", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Label("Aucune clé enregistrée", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    Spacer()
                    if hasStoredKey {
                        Button("Supprimer") {
                            KeychainStore.deleteAPIKey()
                            hasStoredKey = false
                        }
                    }
                    Button("Enregistrer") {
                        let trimmed = apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        KeychainStore.saveAPIKey(trimmed)
                        apiKeyField = ""
                        hasStoredKey = true
                    }
                    .disabled(apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Link("Créer une clé sur console.anthropic.com",
                     destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
            }

            Section("Espace de travail") {
                TextField("Espace de travail", text: $workspaceIDField, prompt: Text("wrkspc_…"))
                    .onChange(of: workspaceIDField) {
                        AppSettings.workspaceID = workspaceIDField
                    }
                Text("Requis uniquement si ta clé est « liée à l'identité » (erreur 400 sinon). Console → Réglages → Workspaces → copier l'ID de l'espace.")
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
                ForEach(ClaudioAction.allCases, id: \.self) { action in
                    HStack(spacing: 10) {
                        IconBadge(systemName: action.symbolName, color: action.tint, size: 22)
                        Text(action.menuTitle)
                        Spacer()
                        KeyboardShortcuts.Recorder("", name: action.shortcutName)
                    }
                }
            } header: {
                Text("Raccourcis globaux")
            } footer: {
                Text("Chaque action s'applique au texte sélectionné, dans n'importe quelle app.")
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
    @State private var selectedModel: ClaudioModel = ClaudioAction.correct.model

    private var isCustomized: Bool { promptText != selectedAction.defaultSystem }

    var body: some View {
        Form {
            Section {
                Picker("Action", selection: $selectedAction) {
                    ForEach(ClaudioAction.allCases, id: \.self) { action in
                        Text(action.menuTitle).tag(action)
                    }
                }
                .onChange(of: selectedAction) {
                    promptText = selectedAction.system
                    selectedModel = selectedAction.model
                }
            }

            Section("Modèle") {
                Picker("Modèle Claude", selection: $selectedModel) {
                    ForEach(ClaudioModel.allCases, id: \.self) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .onChange(of: selectedModel) {
                    AppSettings.setCustomModel(selectedModel, for: selectedAction)
                }
                Text("\(selectedModel.costHint) — \(selectedModel == selectedAction.defaultModel ? "modèle par défaut pour cette action." : "modèle personnalisé, le défaut est \(selectedAction.defaultModel.displayName).")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Prompt système") {
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
                        Label("Personnalisé", systemImage: "pencil")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label("Prompt par défaut", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Réinitialiser") {
                        AppSettings.setCustomSystemPrompt(nil, for: selectedAction)
                        promptText = selectedAction.defaultSystem
                    }
                    .disabled(!isCustomized)
                }
                Text("Modifications appliquées immédiatement. Le texte sélectionné est envoyé à part — balisé <texte_source> pour les actions de prompt — ce prompt ne définit que la tâche.")
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
    @State private var updateMessage: String?
    @State private var updateURL: URL?

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
                        Text("Version \(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Des actions IA sur votre texte sélectionné, partout sur macOS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Mises à jour") {
                HStack {
                    Button("Vérifier maintenant") {
                        checking = true
                        Task { @MainActor in
                            switch await UpdateChecker.shared.checkNow() {
                            case .upToDate:
                                updateMessage = "Claudio est à jour (version \(version))."
                                updateURL = nil
                            case .updateAvailable(let feed):
                                updateMessage = "Mise à jour \(feed.version) disponible."
                                updateURL = feed.url
                            case .failed:
                                updateMessage = "Vérification impossible — réessayez plus tard."
                                updateURL = nil
                            }
                            checking = false
                        }
                    }
                    .disabled(checking)
                    if checking {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if let updateURL {
                        Link("Télécharger", destination: updateURL)
                    }
                }
                if let updateMessage {
                    Text(updateMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text("Vérification automatique une fois par jour — une simple lecture de version.json sur claudio.okonoma.com, aucune donnée envoyée.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link(destination: URL(string: "https://claudio.okonoma.com")!) {
                    Label("Site web", systemImage: "globe")
                }
                Link(destination: URL(string: "https://github.com/gdhios/claudio")!) {
                    Label("Code source (MIT)", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://buymeacoffee.com/gdhios")!) {
                    Label("Offrir un café ☕", systemImage: "heart")
                }
            }

            Section {
                Text("Fait main en Swift. Projet indépendant, non affilié à Anthropic — Claude est une marque d'Anthropic, PBC.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
