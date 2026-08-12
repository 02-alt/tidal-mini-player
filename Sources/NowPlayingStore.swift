import AppKit
import Combine

/// Owns the adapter stream, live-position ticking, and artwork decoding, and
/// publishes the state the menu bar label and player view render.
@MainActor
final class NowPlayingStore: ObservableObject {
    @Published private(set) var now: NowPlaying = .idle
    @Published private(set) var artwork: NSImage?
    /// Ticks once a second so views recompute the live playback position.
    @Published private(set) var tick: Date = .init()

    private var adapter: AdapterClient?
    private var tickTimer: DispatchSourceTimer?
    private var artworkKey: String?
    private let artworkProvider = ArtworkProvider()
    /// The app that currently owns the system "Now Playing" slot (updated for
    /// every source, unlike `now` which is pinned to TIDAL for display).
    private var activeBundleID: String?

    init() {
        start()
    }

    private func start() {
        adapter = AdapterClient { [weak self] payload in
            // Parse + base64-decode off the main thread, then hand off.
            let track = NowPlaying.from(payload: payload)
            let artworkBase64 = payload["artworkData"] as? String
            Task { @MainActor in self?.apply(track, artworkBase64: artworkBase64) }
        }
        adapter?.startStream()

        let tick = DispatchSource.makeTimerSource(queue: .main)
        tick.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(100))
        tick.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick = Date() }
        }
        tick.resume()
        tickTimer = tick
    }

    // MARK: - Menu bar label

    /// Short text shown in the menu bar next to the TIDAL logo, e.g.
    /// "Title — Artist".
    var menuBarTitle: String? {
        guard now.hasTrack, let title = now.title else { return nil }
        let artist = now.artist.map { " — \($0)" } ?? ""
        return truncate(title + artist, to: 30)
    }

    // MARK: - Controls

    func togglePlayPause() { control(.togglePlayPause, ax: .playPause) }
    func next() { control(.nextTrack, ax: .next) }
    func previous() { control(.previousTrack, ax: .previous) }
    func toggleShuffle() { control(.toggleShuffle, ax: .shuffle) }
    func toggleRepeat() { control(.toggleRepeat, ax: .repeatMode) }

    /// Routes a control to TIDAL. When TIDAL owns the Now Playing slot we send a
    /// fast MediaRemote command (no permission needed). Otherwise a MediaRemote
    /// command would hit whatever *does* own the slot (e.g. a browser video), so
    /// we instead press TIDAL's own Playback-menu item via Accessibility — which
    /// targets TIDAL only and leaves the other app alone (see `TidalControl`).
    private func control(_ command: AdapterClient.Command, ax: TidalControl.Command) {
        if activeBundleID == "com.tidal.desktop" {
            adapter?.send(command)
        } else {
            TidalControl.perform(ax)
        }
    }

    func openTidal() {
        let ws = NSWorkspace.shared
        // Resolve TIDAL wherever it's installed (not just /Applications); fall
        // back to the conventional path if Launch Services can't find it.
        if let url = ws.urlForApplication(withBundleIdentifier: "com.tidal.desktop") {
            ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            ws.open(URL(fileURLWithPath: "/Applications/TIDAL.app"))
        }
    }

    // MARK: - State updates

    private func apply(_ new: NowPlaying, artworkBase64: String?) {
        // Track who really owns the Now Playing slot (used to route controls),
        // even though the display below stays pinned to TIDAL.
        activeBundleID = new.bundleIdentifier

        // Only TIDAL drives this player. macOS tracks a single system-wide "Now
        // Playing" app, so when another app (a browser video, Music, …) grabs
        // that slot we simply stop hearing about TIDAL — we don't get told it
        // stopped. Rather than blank out to the music note, keep showing the
        // last TIDAL track (it's almost certainly still playing) until TIDAL
        // reclaims the slot with fresh info.
        guard new.isTidal else { return }

        let trackChanged = new.trackKey != now.trackKey
        now = new

        guard new.hasTrack else {
            artwork = nil
            artworkKey = nil
            return
        }

        if trackChanged {
            artwork = nil
            artworkKey = new.trackKey
        }

        // Decode the embedded thumbnail so something shows immediately, then
        // upgrade to a high-res cover in the background.
        if artwork == nil, let base64 = artworkBase64,
           let data = Data(base64Encoded: base64), let image = NSImage(data: data) {
            artwork = image
        }
        if trackChanged {
            loadHighResArtwork(for: new)
        }
    }

    /// Fetches a large cover for `track` and swaps it in — but only if the same
    /// track is still playing when it arrives, so a quick skip doesn't show the
    /// previous album's art.
    private func loadHighResArtwork(for track: NowPlaying) {
        let key = track.trackKey
        Task { [weak self] in
            guard let self,
                  let image = await self.artworkProvider.highResArtwork(for: track)
            else { return }
            await MainActor.run {
                guard self.now.trackKey == key else { return }
                self.artwork = image
            }
        }
    }

    /// Seeds a fixed state for offscreen previews/snapshots. Stops the live
    /// stream so the injected values aren't overwritten. Not used by the app.
    func previewInject(_ np: NowPlaying, artwork: NSImage?) {
        adapter?.stop(); adapter = nil
        tickTimer?.cancel(); tickTimer = nil
        now = np
        self.artwork = artwork
        artworkKey = np.trackKey
    }

    private func truncate(_ string: String, to max: Int) -> String {
        guard string.count > max else { return string }
        return String(string.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
