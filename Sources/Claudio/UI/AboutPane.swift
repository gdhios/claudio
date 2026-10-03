import SwiftUI

struct AboutPane: View {
    @State private var checking = false
    @State private var installing = false
    // What the daily check has already found: the way to install it is
    // there when the tab opens, without checking again.
    @State private var updateMessage = UpdateChecker.shared.availableUpdate.map(AboutPane.available)
    @State private var pendingUpdate = UpdateChecker.shared.availableUpdate

    private var version: String { Bundle.main.shortVersion }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claudio").font(.title3.bold())
                        Text(loc("Version \(version)", en: "Version \(version)"))
                            .settingsNote()
                        Text(loc("Des actions IA sur votre texte sélectionné, partout sur macOS.",
                                 en: "AI actions on your selected text, anywhere on macOS."))
                            .settingsNote()
                    }
                }
                .padding(.vertical, 4)
            }

            Section(loc("Mises à jour", en: "Updates")) {
                HStack {
                    Button(loc("Vérifier maintenant", en: "Check now")) {
                        checking = true
                        Task { @MainActor in
                            switch await UpdateChecker.shared.checkNow() {
                            case .upToDate:
                                updateMessage = loc("Claudio est à jour (version \(version)).",
                                                    en: "Claudio is up to date (version \(version)).")
                                pendingUpdate = nil
                            case .updateAvailable(let feed):
                                updateMessage = Self.available(feed)
                                pendingUpdate = feed
                            case .failed:
                                updateMessage = loc("Vérification impossible, réessayez plus tard.",
                                                    en: "Could not check, try again later.")
                                pendingUpdate = nil
                            }
                            checking = false
                        }
                    }
                    .disabled(checking || installing)
                    if checking || installing {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if let pendingUpdate {
                        Button(loc("Installer et redémarrer", en: "Install and restart")) { install(pendingUpdate) }
                            .disabled(installing)
                    }
                }
                if let updateMessage {
                    Text(updateMessage).settingsNote()
                }
                Text(loc("Vérification automatique une fois par jour : une simple lecture de version.json sur claudio.okonoma.com, aucune donnée envoyée. L'installation remplace l'app en place et relance Claudio, sans rien laisser dans les Téléchargements.",
                         en: "Checked automatically once a day: a plain read of version.json on claudio.okonoma.com, nothing sent. Installing replaces the app in place and relaunches Claudio, leaving nothing in Downloads."))
                    .settingsNote()
            }

            Section {
                Link(destination: URL(string: "https://claudio.okonoma.com")!) {
                    Label(loc("Site web", en: "Website"), systemImage: "globe")
                }
                Link(destination: URL(string: "https://github.com/gdhios/claudio")!) {
                    Label(loc("Code source (MIT)", en: "Source code (MIT)"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://buymeacoffee.com/gdhios")!) {
                    Label(loc("Offrir un café ☕", en: "Buy me a coffee ☕"), systemImage: "heart")
                }
            }

            Section {
                Text(loc("Fait main en Swift. Projet indépendant, non affilié à Anthropic. Claude est une marque d'Anthropic, PBC.",
                         en: "Hand-made in Swift. Independent project, not affiliated with Anthropic. Claude is a trademark of Anthropic, PBC."))
                    .settingsNote()
            }
        }
        .formStyle(.grouped)
    }

    nonisolated private static func available(_ feed: UpdateChecker.Feed) -> String {
        loc("Mise à jour \(feed.version) disponible.", en: "Update \(feed.version) available.")
    }

    /// Downloads, verifies and installs: on success, the app quits and
    /// the new version relaunches itself.
    private func install(_ feed: UpdateChecker.Feed) {
        installing = true
        updateMessage = loc("Téléchargement de la version \(feed.version)…",
                            en: "Downloading version \(feed.version)…")
        Task { @MainActor in
            do {
                let newApp = try await UpdateInstaller.prepare(from: feed.url)
                try UpdateInstaller.installAndRelaunch(newApp)
            } catch {
                updateMessage = error.localizedDescription
                installing = false
            }
        }
    }
}
