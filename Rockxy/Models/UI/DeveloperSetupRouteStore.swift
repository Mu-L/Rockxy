import Foundation

// MARK: - DeveloperSetupRouteDestination

enum DeveloperSetupRouteDestination: String, Equatable {
    case hub
    case manual
    case automatic
}

// MARK: - DeveloperSetupRoute

struct DeveloperSetupRoute: Equatable {
    let targetID: SetupTarget.ID
    let tab: SetupDetailTab
    let destination: DeveloperSetupRouteDestination
    /// Monotonic generation so a newer route can atomically win over an older
    /// in-flight async route. Consumers compare generations, never wall-clock.
    let generation: Int
}

// MARK: - DeveloperSetupRouteStore

@MainActor @Observable
final class DeveloperSetupRouteStore {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    static let shared = DeveloperSetupRouteStore()

    /// Safe default runtime target used by direct menu entry points that carry
    /// no explicit selection. `.python` is a shipped `runtimeTerminal` target so
    /// both Manual and Automatic flows are valid for it.
    static let defaultRuntimeTargetID: SetupTarget.ID = .python

    /// Pending route for the Developer Setup Hub window.
    private(set) var hubRoute: DeveloperSetupRoute?
    /// Pending route for the Manual Setup window.
    private(set) var manualRoute: DeveloperSetupRoute?
    /// Pending route for the Automatic Setup window.
    private(set) var automaticRoute: DeveloperSetupRoute?

    // MARK: Hub

    func request(targetID: SetupTarget.ID, tab: SetupDetailTab = .setup) {
        hubRoute = makeRoute(targetID: targetID, tab: tab, destination: .hub)
    }

    func consumeHubRoute() -> DeveloperSetupRoute? {
        defer { hubRoute = nil }
        return hubRoute
    }

    // MARK: Manual

    func requestManual(targetID: SetupTarget.ID) {
        manualRoute = makeRoute(targetID: targetID, tab: .setup, destination: .manual)
    }

    func consumeManualRoute() -> DeveloperSetupRoute? {
        defer { manualRoute = nil }
        return manualRoute
    }

    // MARK: Automatic

    /// Automatic Setup is only valid for shipped `runtimeTerminal` targets.
    /// Unsupported targets are rejected here so an automatic window never opens
    /// on a device/browser/framework target.
    @discardableResult
    func requestAutomatic(targetID: SetupTarget.ID) -> Bool {
        guard SetupTarget.target(for: targetID)?.automationSupport == .runtimeTerminal else {
            automaticRoute = nil
            return false
        }
        automaticRoute = makeRoute(targetID: targetID, tab: .setup, destination: .automatic)
        return true
    }

    func consumeAutomaticRoute() -> DeveloperSetupRoute? {
        defer { automaticRoute = nil }
        return automaticRoute
    }

    // MARK: Private

    private var generationCounter = 0

    private func makeRoute(
        targetID: SetupTarget.ID,
        tab: SetupDetailTab,
        destination: DeveloperSetupRouteDestination
    )
        -> DeveloperSetupRoute
    {
        generationCounter += 1
        return DeveloperSetupRoute(
            targetID: targetID,
            tab: tab,
            destination: destination,
            generation: generationCounter
        )
    }
}
