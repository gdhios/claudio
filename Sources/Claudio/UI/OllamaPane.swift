import SwiftUI

@MainActor
struct OllamaPane: View {
    @State private var addressField = AppSettings.ollamaBaseURL.absoluteString
    @State private var testing = false
    @State private var models: [String] = []
    /// Result of the last test: the message, and whether it reports a failure.
    @State private var report: String?
    @State private var failed = false

    var body: some View {
        Form {
            Section(loc("Serveur", en: "Server")) {
                TextField(loc("Adresse", en: "Address"), text: $addressField,
                          prompt: Text(Constants.ollamaDefaultURL.absoluteString))
                    .onSubmit { save() }
                HStack {
                    Button(loc("Tester la connexion", en: "Test connection")) {
                        Task { await testTypedAddress() }
                    }
                    .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                }
                if let report {
                    Label(report, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(failed ? .orange : .secondary)
                }
                Text(loc("Ollama tourne sur ta machine, ou sur un autre Mac du réseau local. Rien n'est envoyé ailleurs qu'à cette adresse, et un appel local ne coûte rien. Sans authentification : Ollama n'en propose pas.",
                         en: "Ollama runs on this Mac, or on another Mac on your local network. Nothing is sent anywhere but this address, and a local call costs nothing. No authentication: Ollama doesn't offer any."))
                    .settingsNote()
            }

            Section(loc("Modèles détectés", en: "Models found")) {
                if models.isEmpty {
                    Text(loc("Aucun modèle détecté. Teste la connexion, et tire un modèle avec « ollama pull qwen2.5:14b ».",
                             en: "No model found. Test the connection, then pull one with “ollama pull qwen2.5:14b”."))
                        .settingsNote()
                } else {
                    ForEach(models, id: \.self) { model in
                        Text(model).monospaced()
                    }
                    Text(loc("Ces modèles se choisissent pour chaque raccourci dans l'onglet Modèles.",
                             en: "Pick one of these per shortcut in the Models tab."))
                        .settingsNote()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // The address kept, tried as it is: opening the tab writes no
            // default into the preferences.
            if PreviewRun.isActive { showFixedState() } else { Task { await test(AppSettings.ollamaBaseURL) } }
        }
    }

    /// Preview: the screen populated with data, without calling the server.
    private func showFixedState() {
        models = LocalModels.frozen
        failed = false
        report = loc("Connexion OK — \(models.count) modèles détectés.",
                     en: "Connected — \(models.count) models found.")
    }

    /// An unreadable address doesn't overwrite the one that worked: the field
    /// falls back to the value kept.
    @discardableResult
    private func save() -> URL? {
        guard let url = AppSettings.normalizedOllamaURL(addressField) else {
            addressField = AppSettings.ollamaBaseURL.absoluteString
            return nil
        }
        AppSettings.ollamaBaseURL = url
        addressField = url.absoluteString
        return url
    }

    /// The button: the address typed is kept first, then tried.
    private func testTypedAddress() async {
        guard let url = save() else {
            models = []
            failed = true
            report = loc("Adresse illisible : attendu « http://machine:11434 ».",
                         en: "Unreadable address: expected “http://host:11434”.")
            return
        }
        await test(url)
    }

    /// Asks the server at `url` which models it has pulled.
    private func test(_ url: URL) async {
        testing = true
        defer { testing = false }

        do {
            let found = try await OllamaClient.reachableModels(at: url)
            models = found
            failed = false
            report = found.isEmpty
                ? loc("Connexion OK, mais aucun modèle tiré sur ce serveur.",
                      en: "Connected, but no model has been pulled on that server.")
                : loc("Connexion OK — \(found.count) modèle\(found.count > 1 ? "s" : "") détecté\(found.count > 1 ? "s" : "").",
                      en: "Connected — \(found.count) model\(found.count > 1 ? "s" : "") found.")
        } catch {
            models = []
            failed = true
            report = error.localizedDescription
        }
    }
}
