import SwiftUI

/// The Stream Deck tab: what the plugin does, whether it has come, and the
/// one switch it needs — on, off, or left to the plugin's presence.
///
/// Everything shown comes from `StreamDeckStatusModel`, which the app fills
/// in: the pane reads no preference, looks in no folder and opens no socket,
/// so a preview renders the same screen on every machine.
@MainActor
struct StreamDeckPane: View {
    @ObservedObject private var model = StreamDeckStatusModel.shared

    var body: some View {
        Form {
            what
            bridge
            download
        }
        .formStyle(.grouped)
        // The plugin may have been installed — or removed — since the last
        // look: the tab asks again every time it opens.
        .onAppear { model.refresh?() }
    }

    // MARK: - What the plugin is for

    private var what: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemName: SettingsSection.streamDeck.symbolName,
                          color: SettingsSection.streamDeck.color)
                Text(loc("Le plugin Stream Deck pilote Claudio depuis tes touches : actions, dictée, fenêtres, et la tête de Claudio quand il attend.",
                         en: "The Stream Deck plugin drives Claudio from your keys: actions, dictation, windows, and Claudio's face while he waits."))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - The bridge

    private var bridge: some View {
        Section {
            Label(statusText, systemImage: statusSymbol)
                .foregroundStyle(statusColor)

            Toggle(loc("Autoriser le plugin à piloter Claudio",
                       en: "Let the plugin drive Claudio"),
                   isOn: Binding(get: { model.isOn }, set: { model.setOn($0) }))

            // Automatic says why it sits where it sits; a choice says how to
            // take it back. One or the other, never both.
            if model.isAutomatic {
                Text(model.pluginInstalled
                     ? loc("Réglé automatiquement : plugin détecté",
                           en: "Set automatically: plugin detected")
                     : loc("Réglé automatiquement : plugin absent",
                           en: "Set automatically: plugin not found"))
                    .settingsNote()
            } else {
                Button(loc("Revenir à l'automatique", en: "Back to automatic")) {
                    model.backToAutomatic()
                }
            }
        } header: {
            Text(loc("État", en: "Status"))
        } footer: {
            Text(loc("Installer le plugin suffit : Claudio ouvre alors un point d'écoute local, jamais exposé au réseau. L'interrupteur n'est là que pour forcer la main — à couper, ou à garder ouvert pour un plugin rangé ailleurs.",
                     en: "Installing the plugin is the whole setup: Claudio then opens a local listening point, never exposed to the network. The switch is only there to force the matter — off, or open for a plugin kept somewhere else."))
                .settingsNote()
        }
    }

    // MARK: - Getting the plugin

    private var download: some View {
        Section {
            Link(destination: URL(string: "https://claudio.okonoma.com/#streamdeck")!) {
                Label(loc("Télécharger le plugin", en: "Download the plugin"),
                      systemImage: "arrow.down.circle")
            }
        }
    }

    // MARK: - The status, said in one line

    private var statusText: String {
        switch model.status {
        case .off: loc("Désactivé", en: "Off")
        case .waiting: loc("En attente du plugin", en: "Waiting for the plugin")
        case .connected: loc("Plugin connecté", en: "Plugin connected")
        }
    }

    private var statusSymbol: String {
        switch model.status {
        case .off: "power"
        case .waiting: "clock"
        case .connected: "checkmark.circle"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .off: .secondary
        case .waiting: .orange
        case .connected: .green
        }
    }
}
