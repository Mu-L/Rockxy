import SwiftUI

/// Combined view showing both request and response HTTP headers in a two-column grid layout.
/// Used as the standalone headers inspector tab in the full-transaction view.
struct HeadersInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Section(String(localized: "Request Headers", bundle: RockxyLocalization.bundle)) {
                    headerTable(headers: transaction.request.headers)
                }

                if let response = transaction.response {
                    Section(String(localized: "Response Headers", bundle: RockxyLocalization.bundle)) {
                        headerTable(headers: response.headers)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: Private

    private func headerTable(headers: [HTTPHeader]) -> some View {
        HeaderKeyValueTable(headers: headers)
    }
}
