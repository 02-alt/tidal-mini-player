import Foundation

/// A snapshot of the current "Now Playing" track, parsed from a
/// mediaremote-adapter payload.
struct NowPlaying: Equatable {
    var bundleIdentifier: String?
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsed: Double?
    var playbackRate: Double?
    var playing: Bool = false
    /// Epoch seconds at which `elapsed` was measured (for live extrapolation).
    var timestamp: Double?
    var contentItemIdentifier: String?

    var isPlaying: Bool { playing }
    var hasTrack: Bool { !(title ?? "").isEmpty }
    var isTidal: Bool { bundleIdentifier == "com.tidal.desktop" }

    /// Stable identity for a track, used for artwork caching / change detection.
    var trackKey: String {
        contentItemIdentifier ?? "\(artist ?? "")|\(album ?? "")|\(title ?? "")"
    }

    /// Live playback position, extrapolated from the last reported timestamp.
    var livePosition: Double {
        guard let elapsed else { return 0 }
        guard let timestamp, isPlaying else { return elapsed }
        let extrapolated = elapsed + (Date().timeIntervalSince1970 - timestamp) * (playbackRate ?? 1)
        if let duration { return min(max(extrapolated, 0), duration) }
        return max(extrapolated, 0)
    }

    static let idle = NowPlaying()

    /// Builds a snapshot from a mediaremote-adapter JSON payload. An empty
    /// payload (`{}`) means nothing is playing and maps to `.idle`.
    static func from(payload: [String: Any]) -> NowPlaying {
        guard !payload.isEmpty else { return .idle }
        var np = NowPlaying()
        np.bundleIdentifier = payload["bundleIdentifier"] as? String
        np.title = nonEmpty(payload["title"])
        np.artist = nonEmpty(payload["artist"])
        np.album = nonEmpty(payload["album"])
        np.duration = number(payload["duration"])
        np.elapsed = number(payload["elapsedTime"])
        np.playbackRate = number(payload["playbackRate"])
        np.playing = (payload["playing"] as? Bool) ?? ((np.playbackRate ?? 0) > 0)
        np.contentItemIdentifier = payload["contentItemIdentifier"] as? String
        if let ts = payload["timestamp"] as? String {
            np.timestamp = isoFormatter.date(from: ts)?.timeIntervalSince1970
        }
        return np
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}
