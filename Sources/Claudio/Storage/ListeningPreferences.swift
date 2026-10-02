import Foundation

/// How much Claude says about the track. The prompt asks for it, and the
/// answer's budget follows. The raw values are storage keys: never renamed.
enum ListeningDetail: String, CaseIterable, Sendable {
    case oneSentence = "one"
    case threeSentences = "three"
    case paragraph = "paragraph"

    var maxTokens: Int {
        switch self {
        case .oneSentence: 150
        case .threeSentences: 400
        case .paragraph: 900
        }
    }

    /// The ask, in the prompt's French: "en …, présente ce qu'il écoute".
    var instruction: String {
        switch self {
        case .oneSentence: "en une phrase"
        case .threeSentences: "en trois phrases courtes au plus"
        case .paragraph: "en un paragraphe de cinq phrases au plus"
        }
    }

    var displayName: String {
        switch self {
        case .oneSentence: loc("Une phrase", en: "One sentence")
        case .threeSentences: loc("Trois phrases", en: "Three sentences")
        case .paragraph: loc("Un paragraphe", en: "A paragraph")
        }
    }
}

/// What the Music tab sets, read once per listening so a change applies to
/// the next one.
struct ListeningPreferences: Equatable, Sendable {
    /// Ask MusicBrainz for the facts, and the archive for a cover. On by
    /// default: decided 2026-10-02.
    var musicBrainz: Bool
    var showsArtwork: Bool
    var detail: ListeningDetail

    static func current(in defaults: UserDefaults = .standard) -> ListeningPreferences {
        ListeningPreferences(musicBrainz: AppSettings.musicBrainzEnabled(in: defaults),
                             showsArtwork: AppSettings.showsArtwork(in: defaults),
                             detail: AppSettings.listeningDetail(in: defaults))
    }
}

extension AppSettings {
    private static let musicBrainzKey = "listening.musicBrainz"
    private static let showsArtworkKey = "listening.artwork"
    private static let listeningDetailKey = "listening.detail"

    static func musicBrainzEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: musicBrainzKey) as? Bool ?? true
    }

    static func setMusicBrainzEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: musicBrainzKey)
    }

    static func showsArtwork(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showsArtworkKey) as? Bool ?? true
    }

    static func setShowsArtwork(_ shows: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(shows, forKey: showsArtworkKey)
    }

    /// A value this version doesn't know falls back to the default.
    static func listeningDetail(in defaults: UserDefaults = .standard) -> ListeningDetail {
        defaults.string(forKey: listeningDetailKey).flatMap(ListeningDetail.init(rawValue:)) ?? .threeSentences
    }

    static func setListeningDetail(_ detail: ListeningDetail, in defaults: UserDefaults = .standard) {
        defaults.set(detail.rawValue, forKey: listeningDetailKey)
    }
}
