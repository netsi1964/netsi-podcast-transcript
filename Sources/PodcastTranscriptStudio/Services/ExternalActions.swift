import AppKit

/// Opens Apple Podcasts and the browser for the external actions on the episode header
/// (PRD-FEAT-013).
enum ExternalActions {
    /// Opens the episode in Apple Podcasts. `atMs` deep-links to a selected timecode when given
    /// (PRD-FEAT-013.2).
    static func openInPodcasts(episode: Episode, atMs: Int? = nil) {
        var urlString = episode.appleURL
        if let atMs {
            let seconds = atMs / 1000
            urlString += (urlString.contains("?") ? "&" : "?") + "t=\(seconds)"
        }
        open(urlString)
    }

    /// Opens the podcast series page so the user can subscribe (PRD-FEAT-013 acceptance).
    static func subscribe(podcast: Podcast) {
        if let url = podcast.appleURL { open(url) }
    }

    /// Opens a Google search prefilled with podcast + episode titles (PRD-FEAT-013.3).
    static func googleSearch(podcast: Podcast?, episode: Episode) {
        let terms = [podcast?.title, episode.title].compactMap { $0 }.joined(separator: " ")
        let encoded = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? terms
        open("https://www.google.com/search?q=\(encoded)")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
