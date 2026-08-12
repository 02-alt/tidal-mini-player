import AppKit
import ApplicationServices

/// Controls TIDAL when it doesn't own the "Now Playing" slot, by pressing items
/// in TIDAL's own **Playback** menu through the Accessibility API.
///
/// A MediaRemote command can't be aimed at a specific app, and TIDAL (Electron)
/// ignores keystrokes while it isn't the focused window. But its native menu bar
/// *is* exposed to Accessibility, and a menu item can be `AXPress`ed while TIDAL
/// stays in the background — no activation, no focus change, no flash, and the
/// app that currently owns the media slot (e.g. a browser video) is untouched.
///
/// This needs the one-time **Accessibility** permission (System Settings →
/// Privacy & Security → Accessibility).
enum TidalControl {
    static let bundleID = "com.tidal.desktop"

    /// A Playback-menu action, identified by the menu item title(s) to match.
    /// (The play/pause item is titled "Play" or "Pause" depending on state.)
    enum Command {
        case playPause, next, previous, shuffle, repeatMode
        var titles: [String] {
            switch self {
            case .playPause:  return ["Play", "Pause"]
            case .next:       return ["Next"]
            case .previous:   return ["Previous"]
            case .shuffle:    return ["Shuffle"]
            case .repeatMode: return ["Repeat"]
            }
        }
    }

    /// Whether the Accessibility permission has been granted to this app.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that guides the user to grant Accessibility.
    /// Harmless (returns true, no dialog) if already granted.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// Presses the matching TIDAL Playback-menu item. No-op (but triggers the
    /// permission prompt once) if Accessibility hasn't been granted yet.
    static func perform(_ command: Command) {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first else { return }
        guard AXIsProcessTrusted() else { promptForAccessibility(); return }

        let pid = app.processIdentifier
        // AX traversal is synchronous; keep it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let appElement = AXUIElementCreateApplication(pid)
            guard let item = playbackMenuItem(in: appElement, titles: command.titles) else { return }
            AXUIElementPerformAction(item, kAXPressAction as CFString)
        }
    }

    // MARK: - Accessibility helpers

    private static func playbackMenuItem(in app: AXUIElement, titles: [String]) -> AXUIElement? {
        guard let menuBar = element(app, kAXMenuBarAttribute) else { return nil }
        for barItem in children(menuBar) where title(barItem) == "Playback" {
            for menu in children(barItem) {
                for menuItem in children(menu) where titles.contains(title(menuItem)) {
                    return menuItem
                }
            }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    private static func title(_ element: AXUIElement) -> String {
        (attribute(element, kAXTitleAttribute as String) as? String) ?? ""
    }
}
