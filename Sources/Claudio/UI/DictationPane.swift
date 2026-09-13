import AppKit
import SwiftUI

/// The Dictation tab: the two languages the shortcuts listen in, the model
/// that tidies the transcript up, the prompt it is given, and the dictations
/// already made. Split out of `SettingsView` like the other panes, because
/// this one carries a list.
@MainActor
struct DictationPane: View {
    // A preview shows fixed settings rather than this Mac's: the shot has to
    // be the same on every machine, and nothing it displays is read from — or
    // written back to — the real preferences.
    @State private var primaryLanguage = PreviewRun.isActive
        ? DictationLanguage.frFR : AppSettings.dictationPrimaryLanguage
    @State private var secondaryLanguage = PreviewRun.isActive
        ? DictationLanguage.enUS : AppSettings.dictationSecondaryLanguage
    @State private var model = PreviewRun.isActive
        ? AppSettings.defaultDictationModel : AppSettings.dictationModel
    @State private var promptText = PreviewRun.isActive
        ? DictationCleanup.defaultSystemPrompt : DictationCleanup.systemPrompt
    /// Models pulled on the Ollama server, read when the pane opens.
    @State private var localModels: [String] = []
    /// The history as it was when the pane opened. Re-read on every open: a
    /// dictation made meanwhile shows up the next time Settings is shown.
    @State private var entries: [RecentDictation] = []

    private var isCustomized: Bool { promptText != DictationCleanup.defaultSystemPrompt }

    /// The already-set model stays offered even if the server doesn't respond:
    /// without it, the picker would show a blank line for a valid setting.
    private var offeredLocalModels: [String] {
        guard case .ollama(let current) = model, !localModels.contains(current) else {
            return localModels
        }
        return [current] + localModels
    }

    var body: some View {
        Form {
            languages
            cleanupModel
            cleanupPrompt
            history
        }
        .formStyle(.grouped)
        .onAppear { load() }
    }

    // MARK: - Languages

    private var languages: some View {
        Section {
            Picker(loc("Langue principale", en: "Primary language"), selection: $primaryLanguage) {
                ForEach(DictationLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .onChange(of: primaryLanguage) { AppSettings.dictationPrimaryLanguage = primaryLanguage }

            Picker(loc("Autre langue", en: "Other language"), selection: $secondaryLanguage) {
                ForEach(DictationLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .onChange(of: secondaryLanguage) { AppSettings.dictationSecondaryLanguage = secondaryLanguage }
        } header: {
            Text(loc("Langues", en: "Languages"))
        } footer: {
            Text(loc("Maintiens le raccourci de dictée et parle : au relâchement, le texte se colle là où était le curseur. Le second raccourci écoute dans l'autre langue. Les deux se règlent dans l'onglet Raccourcis. La langue n'est jamais devinée, et son modèle doit être installé sur le Mac (Réglages Système → Clavier → Dictée).",
                     en: "Hold the dictation shortcut and speak: on release, the text lands where the cursor was. The second shortcut listens in the other language. Both are set in the Shortcuts tab. The language is never guessed, and its model has to be installed on this Mac (System Settings → Keyboard → Dictation)."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Cleanup model

    private var cleanupModel: some View {
        Section(loc("Modèle de nettoyage", en: "Cleanup model")) {
            Picker(loc("Modèle", en: "Model"), selection: $model) {
                Section("Claude") {
                    ForEach(ClaudioModel.allCases, id: \.self) { claude in
                        Text(claude.displayName).tag(ModelChoice.claude(claude))
                    }
                }
                Section(loc("Local (Ollama)", en: "Local (Ollama)")) {
                    ForEach(offeredLocalModels, id: \.self) { name in
                        Text(name).tag(ModelChoice.ollama(model: name))
                    }
                }
                Section(loc("Sans modèle", en: "No model")) {
                    Text(ModelChoice.raw.displayName).tag(ModelChoice.raw)
                }
            }
            .onChange(of: model) { AppSettings.dictationModel = model }

            Text("\(model.costHint). \(model == .raw ? loc("La transcription est collée telle qu'elle a été entendue : sans ponctuation, avec les hésitations.", en: "The transcript is pasted exactly as it was heard: no punctuation, hesitations and all.") : loc("Le modèle ponctue la transcription et retire les hésitations, sans jamais reformuler. S'il échoue, le brut est collé quand même.", en: "The model punctuates the transcript and drops the hesitations, never rephrasing. If it fails, the raw text is pasted anyway."))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if offeredLocalModels.isEmpty {
                Text(loc("Aucun modèle local détecté : règle le serveur dans l'onglet Local (Ollama).",
                         en: "No local model found: set the server up in the Local (Ollama) tab."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Cleanup prompt

    private var cleanupPrompt: some View {
        Section(loc("Prompt de nettoyage", en: "Cleanup prompt")) {
            TextEditor(text: $promptText)
                .font(.callout)
                .frame(minHeight: 180)
                .onChange(of: promptText) {
                    // Same as the default: drop the override, so the prompt
                    // follows the app's updates.
                    AppSettings.dictationSystemPrompt = isCustomized ? promptText : nil
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
                    AppSettings.dictationSystemPrompt = nil
                    promptText = DictationCleanup.defaultSystemPrompt
                }
                .disabled(!isCustomized)
            }
            Text(loc("Envoyé au modèle avec la transcription. Sans effet si le modèle est « Brut ».",
                     en: "Sent to the model along with the transcript. Has no effect when the model is “Raw”."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - History

    private var history: some View {
        Section {
            if entries.isEmpty {
                Text(loc("Aucune dictée pour l'instant.", en: "No dictation yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    row(entry)
                }
            }
        } header: {
            HStack {
                Text(loc("Historique", en: "History"))
                Spacer()
                Button(loc("Effacer", en: "Clear"), role: .destructive) {
                    DictationHistory.shared.clear()
                    entries = []
                }
                .disabled(entries.isEmpty)
                .controlSize(.small)
                .textCase(nil)
            }
        } footer: {
            Text(loc("Les 50 dernières dictées, sur ce Mac seulement : le texte entendu et sa version nettoyée, jamais l'audio.",
                     en: "The last 50 dictations, on this Mac only: the text heard and its cleaned-up version, never the audio."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ entry: RecentDictation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                // Not a word: a separator, which no language translates.
                Text(verbatim: "·")
                Text(languageName(entry.language))
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(entry.cleaned ?? entry.raw)
                .font(.callout)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Button(loc("Copier le brut", en: "Copy raw")) { copy(entry.raw) }
                Button(loc("Copier le nettoyé", en: "Copy cleaned")) { copy(entry.cleaned ?? "") }
                    .disabled(entry.cleaned == nil)
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func languageName(_ identifier: String) -> String {
        DictationLanguage(rawValue: identifier)?.displayName ?? identifier
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Opening the pane

    /// A preview renders the same screen on every machine: it asks no
    /// server for its models, and shows a fixed history instead of whatever
    /// this Mac happens to have dictated.
    private func load() {
        guard !PreviewRun.isActive else {
            localModels = ["qwen2.5:14b", "llama3.2:3b"]
            entries = DictationPane.frozenHistory
            return
        }
        entries = DictationHistory.shared.recents.entries
        Task {
            // Discovery doesn't depend on a model: any one would do,
            // this is only meant to populate the menu.
            localModels = await OllamaClient(baseURL: AppSettings.ollamaBaseURL,
                                             model: "").availableModels()
        }
    }

    /// Three dictations that never happened, for the preview: one cleaned
    /// up, one in the other language, one pasted raw.
    private static var frozenHistory: [RecentDictation] {
        let day = Date(timeIntervalSinceReferenceDate: 811_000_000)
        return [
            RecentDictation(date: day,
                            language: DictationLanguage.frFR,
                            raw: loc("euh bonjour je voulais te dire que la réunion de mardi non mercredi est décalée à quatorze heures",
                                     en: "uh hi i wanted to tell you that tuesday's no wednesday's meeting is pushed to two pm"),
                            cleaned: loc("Bonjour, je voulais te dire que la réunion de mercredi est décalée à quatorze heures.",
                                         en: "Hi, I wanted to tell you that Wednesday's meeting is pushed to two pm.")),
            RecentDictation(date: day.addingTimeInterval(-3_600),
                            language: DictationLanguage.enUS,
                            raw: "can you send me the deck before the call tomorrow morning",
                            cleaned: "Can you send me the deck before the call tomorrow morning?"),
            RecentDictation(date: day.addingTimeInterval(-7_200),
                            language: DictationLanguage.frFR,
                            raw: loc("note pour moi rappeler le comptable lundi",
                                     en: "note to self call the accountant on monday")),
        ]
    }
}
