import AppKit

/// Fetches high-resolution cover art to replace the low-res thumbnail embedded
/// in the Now Playing feed.
///
/// TIDAL only pushes a small thumbnail through MediaRemote, which looks soft
/// when shown full-bleed. We look the album up in Apple's free iTunes Search
/// API (no auth), then upgrade the returned artwork URL to a large size. Misses
/// simply leave the embedded thumbnail in place.
actor ArtworkProvider {
    /// Pixel size requested from iTunes (its CDN resizes on demand).
    private let targetPixels = 1600

    private var cache: [String: NSImage] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    /// Returns a large cover for the track, or `nil` if none can be found.
    /// Results are cached per album so repeated tracks don't re-hit the network.
    func highResArtwork(for track: NowPlaying) async -> NSImage? {
        guard let key = Self.lookupKey(for: track) else { return nil }
        if let cached = cache[key] { return cached }

        guard let url = await searchArtworkURL(for: track),
              let (data, _) = try? await session.data(from: url),
              let image = NSImage(data: data)
        else { return nil }

        cache[key] = image
        return image
    }

    /// Queries the iTunes Search API and upgrades the result to `targetPixels`.
    /// Tries an album lookup first (best cover match) and falls back to a song
    /// lookup, which hits far more often for singles and niche releases.
    private func searchArtworkURL(for track: NowPlaying) async -> URL? {
        let artist = track.artist ?? ""
        var attempts: [(term: String, entity: String)] = []
        if let album = track.album, !album.isEmpty {
            attempts.append(("\(artist) \(album)", "album"))
        }
        if let title = track.title, !title.isEmpty {
            attempts.append(("\(artist) \(title)", "song"))
        }

        for attempt in attempts {
            if let url = await artworkURL(term: attempt.term, entity: attempt.entity, track: track) {
                return url
            }
        }
        return nil
    }

    private func artworkURL(term: String, entity: String, track: NowPlaying) async -> URL? {
        guard let query = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string:
                "https://itunes.apple.com/search?term=\(query)&entity=\(entity)&limit=8&media=music")
        else { return nil }

        guard let (data, _) = try? await session.data(from: searchURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]]
        else { return nil }

        // Only trust a result that actually matches the playing track — otherwise
        // we'd overwrite TIDAL's own (correct) cover with the wrong album's art.
        // If nothing matches, return nil and keep the embedded TIDAL thumbnail.
        guard let match = results.first(where: { Self.result($0, matches: track) }),
              let artworkURL = match["artworkUrl100"] as? String
        else { return nil }

        // iTunes URLs end in "100x100bb.jpg"; swap in a larger dimension.
        let upgraded = artworkURL.replacingOccurrences(
            of: "100x100bb", with: "\(targetPixels)x\(targetPixels)bb")
        return URL(string: upgraded)
    }

    /// Whether an iTunes result is really this track's cover. The artist must
    /// match; then, because cover art is album-level, we prefer matching the
    /// album (collection) name — even a search result for a different song on
    /// the same album carries the right cover. Falls back to a track-title match
    /// for singles or when TIDAL doesn't report an album. Matching is diacritic-
    /// and punctuation-insensitive so stylized names like "DeBÍ TiRAR MáS FOToS"
    /// still line up.
    private static func result(_ r: [String: Any], matches track: NowPlaying) -> Bool {
        guard let artist = track.artist, !artist.isEmpty,
              let resultArtist = r["artistName"] as? String,
              fuzzyMatch(resultArtist, artist)
        else { return false }

        if let album = track.album, !album.isEmpty,
           let collection = r["collectionName"] as? String,
           fuzzyMatch(collection, album) {
            return true
        }
        if let title = track.title, !title.isEmpty,
           let name = r["trackName"] as? String,
           fuzzyMatch(name, title) {
            return true
        }
        return false
    }

    /// Loose equality: fold accents/case, drop non-alphanumerics, then accept if
    /// either string contains the other (handles "… (DtMF)" style suffixes).
    private static func fuzzyMatch(_ a: String, _ b: String) -> Bool {
        let na = normalize(a), nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        return na.contains(nb) || nb.contains(na)
    }

    private static func normalize(_ s: String) -> String {
        String(s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// A stable album-level cache key (artist + album, or artist + title).
    private static func lookupKey(for track: NowPlaying) -> String? {
        let artist = track.artist ?? ""
        let work = track.album ?? track.title ?? ""
        let key = "\(artist)|\(work)".lowercased()
        return key == "|" ? nil : key
    }
}
