import ServiceManagement

/// Wraps macOS 13+ `SMAppService` so the app can register itself as a login item
/// (Start at Login) without a separate helper bundle. Reflected in System
/// Settings → General → Login Items.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("TidalMiniPlayer: login item \(enabled ? "register" : "unregister") failed: \(error)")
        }
    }
}
