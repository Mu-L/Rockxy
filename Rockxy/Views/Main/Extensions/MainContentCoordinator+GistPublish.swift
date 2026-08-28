import AppKit
import Foundation

// MARK: - GistPublishContext

struct GistPublishContext: Identifiable {
    let id = UUID()
    let transactions: [HTTPTransaction]
}

// MARK: - MainContentCoordinator + Gist Publish

extension MainContentCoordinator {
    func publishSelectedTransactionsToGist() {
        let selected = resolveSelectedTransactions()
        guard !selected.isEmpty else {
            activeToast = ToastMessage(
                style: .error,
                text: String(localized: "Select a request to publish to Gist", bundle: RockxyLocalization.bundle)
            )
            return
        }
        presentGistPublish(transactions: selected)
    }

    func publishGistContextSelection(clicked transaction: HTTPTransaction) {
        let selected = selectedTransactionIDs.contains(transaction.id)
            ? resolveSelectedTransactions()
            : [transaction]
        presentGistPublish(transactions: selected)
    }

    /// Always opens the native privacy confirmation, regardless of the global quick-publish preference.
    func reviewSelectedTransactionsForGist() {
        let selected = resolveSelectedTransactions()
        guard !selected.isEmpty else {
            activeToast = ToastMessage(
                style: .error,
                text: String(localized: "Select a request to share", bundle: RockxyLocalization.bundle)
            )
            return
        }
        gistPublishContext = GistPublishContext(transactions: selected)
    }

    func publishTransactionsToGist(
        _ transactions: [HTTPTransaction],
        options: GistPublishOptions
    )
        async throws -> GistPublishResult
    {
        guard let credential = try KeychainGitHubCredentialStorage().load() else {
            throw GistPublishError.notAuthorized
        }

        let payload = try GistPublishPayloadBuilder().build(transactions: transactions, options: options)
        let result = try await GitHubGistClient().createGist(
            payload: payload,
            accessToken: credential.accessToken
        )

        if options.copyURLToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.htmlURL.absoluteString, forType: .string)
        }
        if options.openInBrowser {
            NSWorkspace.shared.open(result.htmlURL)
        }

        activeToast = ToastMessage(
            style: .success,
            text: String(
                localized: "Published \(transactions.count) request\(transactions.count == 1 ? "" : "s") to Gist",
                bundle: RockxyLocalization.bundle
            )
        )
        gistPublishContext = nil
        return result
    }

    // MARK: Private

    private func presentGistPublish(transactions: [HTTPTransaction]) {
        let settings = AppSettingsManager.shared.settings
        if GistPublishConfirmationPolicy.requiresReview(
            askBeforePublishing: settings.githubGistAskBeforePublishing,
            redactsSensitiveData: settings.githubGistRedactSensitiveData
        ) {
            gistPublishContext = GistPublishContext(transactions: transactions)
            return
        }

        Task { @MainActor in
            do {
                _ = try await publishTransactionsToGist(
                    transactions,
                    options: GistPublishOptions(from: AppSettingsManager.shared.settings)
                )
            } catch {
                showExportError(
                    title: String(localized: "Publish to Gist Failed", bundle: RockxyLocalization.bundle),
                    message: error.localizedDescription
                )
            }
        }
    }
}

// MARK: - GistPublishConfirmationPolicy

enum GistPublishConfirmationPolicy {
    static func requiresReview(askBeforePublishing: Bool, redactsSensitiveData: Bool) -> Bool {
        askBeforePublishing || !redactsSensitiveData
    }
}

// MARK: - GistPublishError

enum GistPublishError: LocalizedError, Equatable {
    case notAuthorized

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            String(
                localized: "Authorize GitHub in Settings before publishing to Gist.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}

// MARK: - GistPublishOptions + AppSettings

extension GistPublishOptions {
    init(from settings: AppSettings) {
        self.init(
            visibility: settings.githubGistVisibility,
            redactSensitiveData: settings.githubGistRedactSensitiveData,
            openInBrowser: settings.githubGistOpenInBrowser,
            copyURLToClipboard: settings.githubGistCopyURLToClipboard,
            askBeforePublishing: settings.githubGistAskBeforePublishing
        )
    }
}
