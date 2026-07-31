import SwiftUI

struct BabylonCaptureCommands: Commands {
    // MARK: Internal

    var body: some Commands {
        CommandMenu(String(localized: "Babylon")) {
            Button(String(localized: "Pairing…")) {
                openWindow(id: "babylonPairing")
            }

            Button(String(localized: "Runtime Events…")) {
                openWindow(id: "babylonRuntime")
            }
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
}
