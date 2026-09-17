import Combine
import Foundation

// Observes the upstream proxy configuration for the External Proxy menu items.

// MARK: - ExternalProxyMenuState

@MainActor
final class ExternalProxyMenuState: ObservableObject {
    // MARK: Lifecycle

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        self.isEnabled = UpstreamProxyStore.shared.configuration.isEnabled
        observer = notificationCenter.addObserver(
            forName: .upstreamProxyConfigurationDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    // MARK: Internal

    @Published private(set) var isEnabled: Bool

    func refresh() {
        isEnabled = UpstreamProxyStore.shared.configuration.isEnabled
    }

    // MARK: Private

    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?
}
