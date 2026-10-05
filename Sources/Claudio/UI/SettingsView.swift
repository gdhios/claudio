import SwiftUI

/// A tab of Settings. The raw value is also the tab's name in a
/// `claudio://settings/<name>` link, which the Stream Deck plugin and the
/// website hand out: a case can be added, never renamed.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case apiKey
    case models
    case ollama
    case shortcuts
    case dictation
    case music
    case streamDeck
    case ulanzi
    case tip
    case prompts
    case about

    var id: String { rawValue }

    /// The tab a `claudio://settings/<name>` link names, whatever the case
    /// it was typed in or passed on with.
    init?(linkName: String) {
        let wanted = linkName.lowercased()
        guard let section = Self.allCases.first(where: { $0.rawValue.lowercased() == wanted }) else {
            return nil
        }
        self = section
    }

    var title: String {
        switch self {
        case .general: loc("Général", en: "General")
        case .apiKey: loc("Clé API", en: "API key")
        case .models: loc("Modèles", en: "Models")
        case .ollama: loc("Local (Ollama)", en: "Local (Ollama)")
        case .shortcuts: loc("Raccourcis", en: "Shortcuts")
        case .dictation: loc("Dictée", en: "Dictation")
        case .music: loc("Musique", en: "Music")
        case .streamDeck: loc("Stream Deck", en: "Stream Deck")
        case .ulanzi: loc("Ulanzi", en: "Ulanzi")
        case .tip: loc("Pourboire", en: "Tip")
        case .prompts: loc("Prompts", en: "Prompts")
        case .about: loc("À propos", en: "About")
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape.fill"
        case .apiKey: "key.fill"
        case .models: "cpu.fill"
        case .ollama: "desktopcomputer"
        case .shortcuts: "command"
        case .dictation: "mic.fill"
        case .music: ListeningSession.symbolName
        case .streamDeck: "rectangle.grid.3x2.fill"
        case .ulanzi: "lightbulb.led.fill"
        case .tip: "cup.and.saucer.fill"
        case .prompts: "text.quote"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .apiKey: ClaudioTheme.accent
        case .models: .purple
        case .ollama: .green
        case .shortcuts: .indigo
        case .dictation: .pink
        case .music: ListeningSession.tint
        case .streamDeck: .teal
        case .ulanzi: .yellow
        case .tip: .brown
        case .prompts: .orange
        case .about: .blue
        }
    }
}

/// Settings styled after System Settings: sidebar with colored dots,
/// sections as cards (`.formStyle(.grouped)`).
struct SettingsView: View {
    /// The tab, owned outside the view: whoever opens Settings a second time
    /// on another tab has to be obeyed by the window already on screen.
    @ObservedObject private var selection: SettingsSelection
    /// The interface language, watched under the key `AppSettings.language`
    /// keeps it in: General changes it with this window open, and the
    /// sidebar and the pane have to say everything again in the new one.
    @AppStorage("language") private var language: AppLanguage = .system

    init(selection: SettingsSelection) {
        _selection = ObservedObject(wrappedValue: selection)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: selection.sidebar) { section in
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
            // Built again on every opening and in every language: the window
            // is reused, and a pane that never left it would replay neither
            // its `.onAppear` nor its `.task`, which is where it reads this
            // Mac, and would keep the labels it was built with.
            pane.id(PaneKey(opening: selection.openings, language: language))
        }
        .frame(minWidth: 700, minHeight: 500)
        // The Claude list is a day old at most: asked here, where it is
        // read, and nowhere on the way to an action. Asked again on every
        // opening, since the window outlives this view's first appearance.
        .task(id: selection.openings) { await ModelCatalog.shared.refreshIfStale() }
    }

    /// What a pane is built for: one opening of the window, in one language.
    private struct PaneKey: Hashable {
        let opening: Int
        let language: AppLanguage
    }

    @ViewBuilder private var pane: some View {
        switch selection.section {
        case .general: GeneralPane().navigationTitle(SettingsSection.general.title)
        case .apiKey: APIKeyPane().navigationTitle(SettingsSection.apiKey.title)
        case .models: ModelsPane().navigationTitle(SettingsSection.models.title)
        case .ollama: OllamaPane().navigationTitle(SettingsSection.ollama.title)
        case .shortcuts: ShortcutsPane().navigationTitle(SettingsSection.shortcuts.title)
        case .dictation: DictationPane().navigationTitle(SettingsSection.dictation.title)
        case .music: MusicPane().navigationTitle(SettingsSection.music.title)
        case .streamDeck: StreamDeckPane().navigationTitle(SettingsSection.streamDeck.title)
        case .ulanzi: UlanziPane().navigationTitle(SettingsSection.ulanzi.title)
        case .tip: TipPane().navigationTitle(SettingsSection.tip.title)
        case .prompts: PromptsPane().navigationTitle(SettingsSection.prompts.title)
        case .about: AboutPane().navigationTitle(SettingsSection.about.title)
        }
    }
}
