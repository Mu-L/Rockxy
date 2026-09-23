import SwiftUI

/// Displays request cookies (from Cookie header) and response cookies (from Set-Cookie headers)
/// in a two-column grid layout matching the HeadersInspectorView pattern.
struct CookiesInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        ScrollView {
            if transaction.request.cookies.isEmpty, responseCookies.isEmpty {
                Text(String(localized: "No cookies", bundle: RockxyLocalization.bundle))
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !transaction.request.cookies.isEmpty {
                        Section(String(localized: "Request Cookies", bundle: RockxyLocalization.bundle)) {
                            cookieTable(cookies: transaction.request.cookies)
                        }
                    }

                    if !responseCookies.isEmpty {
                        Section(String(localized: "Response Cookies", bundle: RockxyLocalization.bundle)) {
                            cookieTable(cookies: responseCookies)
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: Private

    private var responseCookies: [HTTPCookie] {
        transaction.response?.setCookies ?? []
    }

    private func cookieTable(cookies: [HTTPCookie]) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(minimum: 120, maximum: 200), alignment: .topLeading),
            GridItem(.flexible(), alignment: .topLeading),
        ], spacing: 4) {
            ForEach(Array(cookies.enumerated()), id: \.offset) { _, cookie in
                Text(String(localized: "Name", bundle: RockxyLocalization.bundle))
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .fontWeight(.semibold)
                HighlightedInspectorText(text: cookie.name, highlightContext: highlightContext)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .textSelection(.enabled)

                Text(String(localized: "Value", bundle: RockxyLocalization.bundle))
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .fontWeight(.semibold)
                HighlightedInspectorText(text: cookie.value, highlightContext: highlightContext)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .textSelection(.enabled)

                Text(String(localized: "Domain", bundle: RockxyLocalization.bundle))
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .fontWeight(.semibold)
                HighlightedInspectorText(text: cookie.domain, highlightContext: highlightContext)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .textSelection(.enabled)

                Text(String(localized: "Path", bundle: RockxyLocalization.bundle))
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .fontWeight(.semibold)
                HighlightedInspectorText(text: cookie.path, highlightContext: highlightContext)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .textSelection(.enabled)

                if cookie.isSecure {
                    Text(String(localized: "Secure", bundle: RockxyLocalization.bundle))
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .fontWeight(.semibold)
                    Text(String(localized: "Yes", bundle: RockxyLocalization.bundle))
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .textSelection(.enabled)
                }

                if cookie.isHTTPOnly {
                    Text("HttpOnly")
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .fontWeight(.semibold)
                    Text(String(localized: "Yes", bundle: RockxyLocalization.bundle))
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .textSelection(.enabled)
                }

                if let expires = cookie.expiresDate {
                    Text(String(localized: "Expires", bundle: RockxyLocalization.bundle))
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .fontWeight(.semibold)
                    Text(TimestampFormatter.string(expires, date: .numeric, time: .shortened))
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .textSelection(.enabled)
                }

                Divider()
                    .gridCellColumns(2)
            }
        }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}
