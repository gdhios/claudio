import AppKit

/// "Search in Claude": the card hands the subject to Claude in the browser,
/// where he searches the web before answering — no key, no API cost, and
/// a text that reads its sources rather than its memory. The link is a new
/// conversation on claude.ai with the prompt in `q`, written in the
/// interface's language since it is read there, not by the API.
enum ClaudeSearch {
    static let baseURL = URL(string: "https://claude.ai/new")!
    /// Claude Desktop's own scheme, as Anthropic documents it ("Open Claude
    /// Desktop with a link", read 2026-10-03): same path, `q` prefills the
    /// prompt without sending it. The app comes forward instead of a tab.
    static let desktopProbe = URL(string: "claude://claude.ai/new")!
    /// The address bar has its limits: the latest releases only.
    static let maxReleases = 20

    /// Whether an app on this Mac opens `claude://` links. Asked at each
    /// click: installed or removed since, the next one knows.
    @MainActor
    static func desktopInstalled() -> Bool {
        !PreviewRun.isActive && NSWorkspace.shared.urlForApplication(toOpen: desktopProbe) != nil
    }

    static func url(for subject: MusicSubject, artist: ArtistFacts?,
                    language: AppLanguage = AppSettings.language, desktop: Bool) -> URL {
        var components = URLComponents(url: desktop ? desktopProbe : baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: prompt(for: subject, artist: artist, language: language))]
        return components.url!
    }

    /// Search first, then the subject with its facts, then the discography
    /// the long text got — the facts Claude is to check against.
    static func prompt(for subject: MusicSubject, artist: ArtistFacts?,
                       language: AppLanguage = AppSettings.language) -> String {
        let english = language.showsEnglish
        var parts: [String] = []
        let facts = [subject.firstReleaseDate.map { String($0.prefix(4)) },
                     subject.type.map { TrackFacts.typeName($0, english: english) }]
            .compactMap { $0 }
        let detail = facts.isEmpty ? "" : " (\(facts.joined(separator: ", ")))"
        switch (subject.kind, english) {
        case (.album, false):
            parts.append("Cherche sur le web avant de répondre, puis présente-moi l'album « \(subject.title ?? "") » de \(subject.artist)\(detail) : contexte de sortie, ce qui le distingue, accueil, par quoi commencer.")
        case (.album, true):
            parts.append("Search the web before answering, then introduce the album “\(subject.title ?? "")” by \(subject.artist)\(detail): the context of its release, what sets it apart, its reception, where to start.")
        case (.artist, false):
            parts.append("Cherche sur le web avant de répondre, puis présente-moi l'artiste \(subject.artist) : parcours, ce qui le caractérise, par quoi commencer.")
        case (.artist, true):
            parts.append("Search the web before answering, then introduce the artist \(subject.artist): their path, what characterises them, where to start.")
        }
        if let artist {
            var known: [String] = []
            if let country = artist.country { known.append(english ? "country \(country)" : "pays \(country)") }
            if let begin = artist.beginDate {
                known.append(english ? "active since \(begin)" : "depuis \(begin)")
            }
            if !known.isEmpty {
                parts.append((english ? "Known facts (MusicBrainz): " : "Faits connus (MusicBrainz) : ") + known.joined(separator: ", ") + ".")
            }
            if !artist.releases.isEmpty {
                let kept = artist.releases.suffix(maxReleases)
                let list = kept.map { release in
                    let type = release.primaryType.map { TrackFacts.typeName($0, english: english) }
                    return "\(release.title) (\([release.year, type].compactMap { $0 }.joined(separator: ", ")))"
                }
                let more = kept.count < artist.releases.count ? (english ? ", among others" : ", entre autres") : ""
                parts.append((english ? "Known discography (MusicBrainz): " : "Discographie connue (MusicBrainz) : ")
                             + list.joined(separator: english ? "; " : " ; ") + more + ".")
            }
        }
        parts.append(english ? "Cite nothing you are not sure of." : "Ne cite rien dont tu ne sois pas sûr.")
        return parts.joined(separator: " ")
    }
}
