import Foundation

/// Vérificateur de mise à jour minimaliste : une lecture de version.json sur le
/// site (aucune donnée envoyée), au lancement puis une fois par jour.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Feed: Decodable, Sendable {
        let version: String
        let url: URL
    }

    /// `failed` est distinct de `upToDate` pour que l'UI ne dise jamais
    /// « à jour » sur une simple erreur réseau.
    enum CheckOutcome {
        case upToDate(String)
        case updateAvailable(Feed)
        case failed
    }

    /// Appelé quand une version plus récente est détectée (item du menu status).
    var onUpdateFound: ((Feed) -> Void)?
    private(set) var availableUpdate: Feed?

    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// La version du flux dépasse-t-elle celle installée ? Comparaison
    /// numérique champ à champ : « 1.10.0 » dépasse « 1.9.9 », là où l'ordre
    /// alphabétique inverserait. Égale ou plus ancienne (flux revenu en
    /// arrière) → rien n'est proposé.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    /// Vérification au lancement, puis quotidienne (tolérance large : le moment
    /// exact n'a aucune importance, autant laisser macOS regrouper les réveils).
    func startPeriodicChecks() {
        Task { _ = await checkNow() }
        let timer = Timer.scheduledTimer(withTimeInterval: Constants.updateCheckInterval,
                                         repeats: true) { _ in
            Task { @MainActor in _ = await UpdateChecker.shared.checkNow() }
        }
        timer.tolerance = 3600
        self.timer = timer
    }

    func checkNow() async -> CheckOutcome {
        var request = URLRequest(url: Constants.updateFeedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed
            }
            let feed = try JSONDecoder().decode(Feed.self, from: data)
            if Self.isNewer(feed.version, than: currentVersion) {
                availableUpdate = feed
                onUpdateFound?(feed)
                return .updateAvailable(feed)
            }
            return .upToDate(feed.version)
        } catch {
            return .failed
        }
    }
}
