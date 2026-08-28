import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
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

            Section("Raccourci") {
                KeyboardShortcuts.Recorder("Corriger la sélection :", name: .correctSelection)
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
        .frame(width: 440, height: 460)
    }
}
