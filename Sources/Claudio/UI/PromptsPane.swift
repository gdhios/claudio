import SwiftUI

struct PromptsPane: View {
    @State private var selectedAction: ClaudioAction = .correct
    @State private var promptText: String = ClaudioAction.correct.system
    /// Models pulled on the Ollama server, read when the pane opens.
    @State private var localModels: [String] = []

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
                }
            }

            Section(loc("Modèle", en: "Model")) {
                // The Models tab's row, built again for each action: it
                // reads its slot once, when built.
                ModelSlotRow(slot: .action(selectedAction), localModels: localModels,
                             title: loc("Modèle de cette action", en: "Model for this action"))
                    .id(selectedAction)
                if localModels.isEmpty {
                    NoLocalModelHint()
                }
            }

            Section(loc("Prompt système", en: "System prompt")) {
                TextEditor(text: $promptText)
                    .font(.callout)
                    .frame(minHeight: 260)
                    .onChange(of: promptText) {
                        // Same as the default: remove the override (follows app updates).
                        AppSettings.setCustomSystemPrompt(isCustomized ? promptText : nil,
                                                          for: selectedAction)
                    }
                PromptStatusRow(isCustomized: isCustomized) {
                    AppSettings.setCustomSystemPrompt(nil, for: selectedAction)
                    promptText = selectedAction.defaultSystem
                }
                Text(loc("Modifications appliquées immédiatement. Le texte sélectionné est envoyé à part, balisé <texte_source> pour les actions de prompt : ce prompt ne définit que la tâche. Les prompts par défaut sont écrits en français, et demandent à Claude de répondre dans la langue du texte sélectionné.",
                         en: "Changes take effect immediately. The selected text is sent separately, wrapped in <texte_source> for the prompt actions: this prompt only defines the task. The default prompts are written in French, and ask Claude to answer in the language of the selected text."))
                    .settingsNote()
            }
        }
        .formStyle(.grouped)
        .task { localModels = await LocalModels.discover() }
    }
}
