import SwiftUI

struct APIKeyPane: View {
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
                        guard KeychainStore.saveAPIKey(trimmed) else { return }
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
                    .settingsNote()
            }
        }
        .formStyle(.grouped)
    }
}
