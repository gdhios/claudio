import SwiftUI

/// The one model picker, wherever a model is chosen: the Claude models of
/// the catalog, flagged when the API added them, the local models the Ollama
/// server has pulled, and "Raw" where no model is a valid answer. The chosen
/// model stays offered even when neither list has it: a picker with no row
/// for its value would show a blank line.
struct ModelPicker: View {
    let title: String
    @Binding var selection: ModelChoice
    /// Models pulled on the Ollama server, as `LocalModels.discover` found them.
    let localModels: [String]
    let allowsRaw: Bool
    @ObservedObject private var catalog = ModelCatalog.shared

    init(_ title: String, selection: Binding<ModelChoice>, localModels: [String], allowsRaw: Bool = false) {
        self.title = title
        _selection = selection
        self.localModels = localModels
        self.allowsRaw = allowsRaw
    }

    private var offeredLocalModels: [String] {
        guard case .ollama(let current) = selection, !localModels.contains(current) else {
            return localModels
        }
        return [current] + localModels
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Section("Claude") {
                ForEach(catalog.models.offering(selection), id: \.self) { model in
                    Text(model.pickerLabel(isNew: catalog.isNew(model))).tag(ModelChoice.claude(model))
                }
            }
            Section(loc("Local (Ollama)", en: "Local (Ollama)")) {
                ForEach(offeredLocalModels, id: \.self) { name in
                    Text(name).tag(ModelChoice.ollama(model: name))
                }
            }
            if allowsRaw {
                Section(loc("Sans modèle", en: "No model")) {
                    Text(ModelChoice.raw.displayName).tag(ModelChoice.raw)
                }
            }
        }
    }
}

/// The local models a pane offers, read once when it opens.
enum LocalModels {
    /// What a preview shows: the same two names on every machine.
    static let frozen = ["qwen2.5:14b", "llama3.2:3b"]

    /// The models the Ollama server has pulled, `frozen` in a preview, which
    /// never talks to the network.
    @MainActor
    static func discover() async -> [String] {
        guard !PreviewRun.isActive else { return frozen }
        return await OllamaClient.availableModels(at: AppSettings.ollamaBaseURL)
    }
}

/// The line under a picker: what the choice costs, and whether it is the
/// code's default for this slot.
struct ModelChoiceCaption: View {
    let choice: ModelChoice
    let defaultChoice: ModelChoice

    var body: some View {
        Text("\(choice.costHint). \(choice == defaultChoice ? loc("Modèle par défaut pour cette action.", en: "Default model for this action.") : loc("Modèle personnalisé, le défaut est \(defaultChoice.displayName).", en: "Custom model; the default is \(defaultChoice.displayName)."))")
            .settingsNote()
    }
}

/// Said once per pane when no local model was found.
struct NoLocalModelHint: View {
    var body: some View {
        Text(loc("Aucun modèle local détecté : règle le serveur dans l'onglet Local (Ollama).",
                 en: "No local model found: set the server up in the Local (Ollama) tab."))
            .settingsNote()
    }
}
