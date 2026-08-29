import SwiftUI

// MARK: - SettingsWindowScene

/// Settings deliberately uses the same normal utility-window contract as
/// Developer Setup. A SwiftUI `Settings` scene places the automatic sidebar
/// toggle inside the content region; the normal `Window` scene lets macOS keep
/// that toggle in the unified title bar where it belongs.
struct SettingsWindowScene: Scene {
    // MARK: Internal

    var body: some Scene {
        settingsWindow
    }

    // MARK: Private

    private var settingsWindow: some Scene {
        let base = Window(String(localized: "Settings", bundle: RockxyLocalization.bundle), id: "settings") {
            AppUIDisplayMetricsProvider {
                SettingsView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 1_000, height: 640)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentMinSize)

        if #available(macOS 15.0, *) {
            return base.restorationBehavior(.disabled)
        } else {
            return base
        }
    }
}
