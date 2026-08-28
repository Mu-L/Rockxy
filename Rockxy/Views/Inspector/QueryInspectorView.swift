import SwiftUI

/// Parses and displays URL query parameters from the request URL in a name/value grid.
struct QueryInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        let components = URLComponents(url: transaction.request.url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        Group {
            if queryItems.isEmpty {
                InspectorEmptyStateView(
                    String(localized: "No Query Parameters", bundle: RockxyLocalization.bundle),
                    systemImage: "questionmark.circle"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 100, maximum: 200), alignment: .topLeading),
                        GridItem(.flexible(), alignment: .topLeading),
                    ], spacing: 4) {
                        Text(String(localized: "Name", bundle: RockxyLocalization.bundle))
                            .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Value", bundle: RockxyLocalization.bundle))
                            .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        ForEach(Array(queryItems.enumerated()), id: \.offset) { _, item in
                            HighlightedInspectorText(text: item.name, highlightContext: highlightContext)
                                .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                                .fontWeight(.semibold)
                            HighlightedInspectorText(text: item.value ?? "", highlightContext: highlightContext)
                                .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
}
