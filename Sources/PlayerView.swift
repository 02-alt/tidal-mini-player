import SwiftUI

/// A compact, art-forward player styled after TIDAL's floating mini player:
/// full-bleed album artwork with the title, artist, progress and transport
/// controls overlaid on a dark scrim, in a rounded square.
struct PlayerView: View {
    @ObservedObject var store: NowPlayingStore

    private let side: CGFloat = 372

    var body: some View {
        ZStack {
            background
            scrim
            overlayContent
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .fixedSize()
        .colorScheme(.dark)
        .contextMenu {
            Button("Open TIDAL") { store.openTidal() }
            Toggle("Launch at Login", isOn: Binding(
                get: { LoginItem.isEnabled },
                set: { LoginItem.setEnabled($0) }))
            if !TidalControl.hasAccessibility {
                Button("Enable Background Controls…") { TidalControl.promptForAccessibility() }
            }
            Divider()
            Button("Quit Tidal Mini Player") { NSApp.terminate(nil) }
        }
    }

    // MARK: - Background

    @ViewBuilder private var background: some View {
        if let image = store.artwork {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipped()
        } else {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.17, blue: 0.20),
                         Color(red: 0.04, green: 0.04, blue: 0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(idleMark)
        }
    }

    /// The TIDAL triangle+wave mark, shown as a faint watermark when nothing is
    /// playing — same tint the old music-note glyph used (white at 25%).
    @ViewBuilder private var idleMark: some View {
        if let mark = Self.idleMarkImage {
            Image(nsImage: mark)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 132)
                .foregroundStyle(.white.opacity(0.25))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    private static let idleMarkImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "IdleMark", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    /// Darkens the top (for the menu button) and bottom (for text/controls).
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.45), location: 0.0),
                .init(color: .black.opacity(0.0), location: 0.28),
                .init(color: .black.opacity(0.0), location: 0.45),
                .init(color: .black.opacity(0.85), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Overlay

    private var overlayContent: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if store.now.hasTrack {
                trackInfo
            } else {
                idleInfo
            }
        }
        .padding(14)
    }

    private var topBar: some View {
        HStack {
            Button { store.openTidal() } label: {
                CircleGlyph(system: "arrow.up.forward")
            }
            .buttonStyle(.plain)
            .help("Open TIDAL")
            .accessibilityLabel("Open TIDAL")

            Spacer()
        }
    }

    // MARK: - Track state

    private var trackInfo: some View {
        let track = store.now
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title ?? "")
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2)
                Text(track.artist ?? "Unknown Artist")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)

            progressBar
            controls
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressBar: some View {
        let _ = store.tick // re-render every second
        let position = store.now.livePosition
        let duration = store.now.duration ?? 0
        let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
        return VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.white)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 3)

            HStack {
                Text(timeString(position))
                Spacer()
                Text(timeString(duration))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var controls: some View {
        HStack(spacing: 24) {
            ControlButton(system: "shuffle", label: "Shuffle", size: 15, dim: true) { store.toggleShuffle() }
            ControlButton(system: "backward.fill", label: "Previous", size: 19) { store.previous() }
            ControlButton(
                system: store.now.isPlaying ? "pause.fill" : "play.fill",
                label: store.now.isPlaying ? "Pause" : "Play",
                size: 30
            ) { store.togglePlayPause() }
            ControlButton(system: "forward.fill", label: "Next", size: 19) { store.next() }
            ControlButton(system: "repeat", label: "Repeat", size: 15, dim: true) { store.toggleRepeat() }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Idle state

    private var idleInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing playing")
                .font(.system(size: 16, weight: .bold))
            Text("Start a track in TIDAL")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            controls
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Building blocks

/// A translucent circular icon button used for the top-bar actions.
private struct CircleGlyph: View {
    let system: String
    var body: some View {
        Image(systemName: system)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(.black.opacity(0.35), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .contentShape(Circle())
    }
}

private struct ControlButton: View {
    let system: String
    let label: String
    let size: CGFloat
    var dim: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(dim ? (hovering ? 0.95 : 0.7) : 1))
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .frame(width: size + 14, height: size + 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .scaleEffect(hovering ? 1.12 : 1.0)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}
