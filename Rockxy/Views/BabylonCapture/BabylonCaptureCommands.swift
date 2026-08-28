import SwiftUI

struct BabylonCaptureCommands: Commands {
    // MARK: Internal

    var body: some Commands {
        CommandMenu(String(localized: "Babylon", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Pairing…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "babylonPairing")
            }

            Button(String(localized: "Runtime Events…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "babylonRuntime")
            }
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
}
