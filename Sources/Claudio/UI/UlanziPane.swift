import SwiftUI

/// The Ulanzi tab: what the clocks are for, one card per clock, a button to
/// add one, then the Claude Code relay and its hook.
///
/// Everything shown comes from `UlanziStatusModel`, which the app fills in:
/// the pane reads no preference, calls no device and opens no file, so a
/// preview renders the same screen on every machine, and its buttons do
/// nothing.
struct UlanziPane: View {
    @ObservedObject private var model = UlanziStatusModel.shared
    /// The cards as typed; the clocks kept are the model's.
    @State private var drafts = UlanziStatusModel.shared.drafts

    var body: some View {
        Form {
            what
            ForEach($drafts) { $draft in
                UlanziClockCard(draft: $draft,
                                row: model.clocks.first { $0.id == draft.id },
                                unreadable: model.unreadable.contains(draft.id),
                                isFirst: draft.id == drafts.first?.id,
                                submit: { submit(draft.id) },
                                test: { test(draft.id) },
                                remove: { remove(draft.id) })
            }
            adding
            UlanziClaudeCodeSection(model: model)
        }
        .formStyle(.grouped)
    }

    // MARK: - What the clocks are for

    private var what: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemName: SettingsSection.ulanzi.symbolName,
                          color: SettingsSection.ulanzi.color)
                Text(loc("Claudio parle à tes Ulanzi TC001 sous AWTRIX NG : son visage pendant qu'il travaille, et les fanions de tes sessions Claude Code.",
                         en: "Claudio talks to your Ulanzi TC001 running AWTRIX NG: his face while he works, and the flags of your Claude Code sessions."))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Adding a clock

    private var adding: some View {
        Section {
            if drafts.isEmpty {
                Text(loc("Aucune horloge", en: "No clock"))
                    .foregroundStyle(.secondary)
            }
            Button(loc("Ajouter une horloge", en: "Add a clock")) {
                drafts.append(model.newDraft(among: drafts))
            }
        } header: {
            if drafts.isEmpty { Text(loc("Horloges", en: "Clocks")) }
        } footer: {
            Text(loc("Rien n'est envoyé ailleurs qu'à ces adresses, sur ton réseau local. Le visage s'installe tout seul sur chaque appareil.",
                     en: "Nothing is sent anywhere but these addresses, on your local network. The face installs itself on each device."))
                .settingsNote()
        }
    }

    // MARK: - What the cards ask

    /// Each card asks for itself alone: the clock it shows is kept as
    /// typed, then shown as kept, an address made callable or the clock's
    /// own back in place of one nobody could call. Every other card stays
    /// as typed, neither applied nor lost.
    private func submit(_ id: UUID) {
        model.submit(id, in: drafts)
        drafts = model.redrafted(drafts, after: id)
    }

    private func test(_ id: UUID) {
        model.testTyped(id, in: drafts)
        drafts = model.redrafted(drafts, after: id)
    }

    private func remove(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        model.remove(id)
    }
}
