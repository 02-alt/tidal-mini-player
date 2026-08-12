import AppKit
import Combine
import SwiftUI

@main
struct TidalMiniPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // No SwiftUI scene: the UI is a status item + a custom borderless panel
        // managed by the AppDelegate, so we get full control over the window
        // (no macOS 26 "Liquid Glass" border around the player).
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NowPlayingStore()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var outsideClickMonitor: Any?
    private var cancellable: AnyCancellable?

    private let panelSide: CGFloat = 372

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
        }
        buildPanel()
        updateStatusButton()

        // Refresh the menu bar text whenever the track changes.
        cancellable = store.$now
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusButton() }
    }

    // MARK: - Status button

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.tidalLogoImage
        if let title = store.menuBarTitle {
            button.title = " " + title       // small gap between logo and text
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    /// The TIDAL brand mark — three diamonds in a row plus one centered below —
    /// drawn as a template image so it tints to the menu bar's light/dark
    /// appearance (unlike the app's black-squircle icon).
    private static let tidalLogoImage: NSImage = {
        let centers: [(CGFloat, CGFloat)] = [(0, 1), (1, 1), (2, 1), (1, 0)] // (col, row), y-up
        let r: CGFloat = 0.39        // diamond half-diagonal, in unit-spacing terms
        let pad: CGFloat = 0.16      // padding around the mark, in the same units
        let spanX = 2 + 2 * r + 2 * pad
        let spanY = 1 + 2 * r + 2 * pad
        let height: CGFloat = 16
        let scale = height / spanY

        let image = NSImage(size: NSSize(width: spanX * scale, height: height), flipped: false) { _ in
            NSColor.black.setFill()
            for (cx, cy) in centers {
                let x = (cx + r + pad) * scale
                let y = (cy + r + pad) * scale
                let rr = r * scale
                let path = NSBezierPath()
                path.move(to: NSPoint(x: x + rr, y: y))
                path.line(to: NSPoint(x: x, y: y + rr))
                path.line(to: NSPoint(x: x - rr, y: y))
                path.line(to: NSPoint(x: x, y: y - rr))
                path.close()
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "TIDAL Mini Player"
        return image
    }()

    // MARK: - Panel

    private func buildPanel() {
        let hosting = NSHostingView(rootView: PlayerView(store: store))
        hosting.frame = NSRect(x: 0, y: 0, width: panelSide, height: panelSide)
        // Force CoreAnimation backing so the SwiftUI content actually draws in
        // a transparent (non-opaque) window.
        hosting.wantsLayer = true

        let panel = KeyablePanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        self.panel = panel
    }

    @objc private func togglePanel() {
        panel.isVisible ? closePanel() : openPanel()
    }

    private func openPanel() {
        positionPanel()
        panel.makeKeyAndOrderFront(nil)

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            let click = NSEvent.mouseLocation
            let inPanel = self.panel.frame.contains(click)
            let inButton = self.statusButtonScreenFrame()?.contains(click) ?? false
            if !inPanel && !inButton { self.closePanel() }
        }
    }

    private func closePanel() {
        panel.orderOut(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func positionPanel() {
        guard let frame = statusButtonScreenFrame(),
              let screen = statusItem.button?.window?.screen ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        // Hang below the item, horizontally centered on it, clamped on-screen.
        var origin = NSPoint(x: frame.midX - panelSide / 2, y: frame.minY - panelSide - 6)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panelSide - 8)
        panel.setFrameOrigin(origin)
    }

    private func statusButtonScreenFrame() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}

/// A borderless panel that can still become key, so the SwiftUI transport
/// controls inside stay interactive.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
