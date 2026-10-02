import SwiftUI

/// The Models tab: every shortcut that calls a model, each with its picker,
/// its cost and the reminder of its default. The prompts stay in Prompts and
/// the dictation's languages in Dictation; here only the model is set. The
/// same settings as those tabs' own pickers: a change here shows there.
@MainActor
struct ModelsPane: View {
    @State private var localModels: [String] = []

    var body: some View {
        Form {
            Section {
                ForEach(ClaudioAction.allCases, id: \.self) { action in
                    ModelSlotRow(slot: .action(action), localModels: localModels)
                }
            } header: {
                Text(loc("Actions sur la sélection", en: "Actions on the selection"))
            } footer: {
                Text(loc("Les prompts de ces actions se règlent dans l'onglet Prompts.",
                         en: "These actions' prompts are set in the Prompts tab."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(loc("Action libre", en: "Custom action")) {
                ModelSlotRow(slot: .freeAction, localModels: localModels)
            }

            Section(SettingsSection.dictation.title) {
                ModelSlotRow(slot: .dictation, localModels: localModels)
            }

            Section(ListeningSession.panelTitle) {
                ModelSlotRow(slot: .listening, localModels: localModels)
            }

            Section {
                Text(loc("Les modèles Claude viennent de la liste de l'API, relue une fois par jour à l'ouverture des Réglages ; « nouveau » marque ceux que cette version de Claudio n'embarquait pas. Le local est gratuit et ne sort pas de ta machine.",
                         en: "The Claude models come from the API's list, read once a day when Settings open; “new” marks those this version of Claudio didn't ship with. Local models are free and never leave your Mac."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if localModels.isEmpty {
                    NoLocalModelHint()
                }
            }
        }
        .formStyle(.grouped)
        .task { localModels = await LocalModels.discover() }
    }
}

/// One shortcut's line: its picker, and under it the cost and the default.
/// A preview shows the defaults rather than this Mac's settings: the shot
/// has to be the same on every machine.
@MainActor
private struct ModelSlotRow: View {
    let slot: ModelSlot
    let localModels: [String]
    @State private var choice: ModelChoice

    init(slot: ModelSlot, localModels: [String]) {
        self.slot = slot
        self.localModels = localModels
        _choice = State(initialValue: PreviewRun.isActive ? slot.defaultChoice : slot.current())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ModelPicker(slot.title, selection: $choice, localModels: localModels, allowsRaw: slot.allowsRaw)
                .onChange(of: choice) { slot.set(choice) }
            ModelChoiceCaption(choice: choice, defaultChoice: slot.defaultChoice)
        }
    }
}
