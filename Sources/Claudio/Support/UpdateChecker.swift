import Foundation

/// Minimalist update checker: a read of version.json on the site (no data
/// sent), at launch and then once a day.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Feed: Decodable, Sendable {
        let version: String
        let url: URL
    }

    /// `failed` is distinct from `upToDate` so the UI never says "up to date"
    /// on a plain network error.
    enum CheckOutcome {
        case upToDate(String)
        case updateAvailable(Feed)
        case failed
    }

    /// Called when a newer version is detected (status menu item).
    var onUpdateFound: ((Feed) -> Void)?
    private(set) var availableUpdate: Feed?

    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Does the feed's version exceed the installed one? Numeric,
    /// field-by-field comparison: "1.10.0" beats "1.9.9", where alphabetical
    /// order would reverse it. Equal or older (feed rolled back) means
    /// nothing is offered.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    /// Checked at launch, then daily (wide tolerance: the exact moment
    /// doesn't matter, so let macOS batch the wakeups).
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
