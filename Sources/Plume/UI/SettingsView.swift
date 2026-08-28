import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("Général", systemImage: "gearshape") }
            PromptSettingsTab()
                .tabItem { Label("Prompts", systemImage: "text.quote") }
        }
        .frame(width: 520, height: 600)
    }
}

private struct GeneralSettingsTab: View {
    @State private var apiKeyField = ""
    @State private var hasStoredKey = KeychainStore.loadAPIKey() != nil
    @State private var workspaceIDField = AppSettings.workspaceID ?? ""
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

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

                TextField("Espace de travail", text: $workspaceIDField, prompt: Text("wrkspc_…"))
                    .onChange(of: workspaceIDField) {
                        AppSettings.workspaceID = workspaceIDField
                    }
                Text("Requis uniquement si ta clé est « liée à l'identité » (erreur 400 sinon). Console → Réglages → Workspaces → copier l'ID de l'espace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Raccourcis") {
                ForEach(PlumeAction.allCases, id: \.self) { action in
                    KeyboardShortcuts.Recorder("\(action.menuTitle) :", name: action.shortcutName)
                }
            }

            Section("Général") {
                Toggle("Lancer à l'ouverture de session", isOn: $launchAtLogin)
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
                Text("Modèle : \(Constants.model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PromptSettingsTab: View {
    @State private var selectedAction: PlumeAction = .correct
    @State private var promptText: String = PlumeAction.correct.system

    private var isCustomized: Bool { promptText != selectedAction.defaultSystem }

    var body: some View {
        Form {
            Section {
                Picker("Action", selection: $selectedAction) {
                    ForEach(PlumeAction.allCases, id: \.self) { action in
                        Text(action.menuTitle).tag(action)
                    }
                }
                .onChange(of: selectedAction) {
                    promptText = selectedAction.system
                }
            }

            Section("Prompt système") {
                TextEditor(text: $promptText)
                    .font(.callout)
                    .frame(minHeight: 280)
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
