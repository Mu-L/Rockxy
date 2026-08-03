import SwiftUI

/// Left half of the inspector split view. Provides tabbed access to request-side data:
/// headers, query parameters, body, cookies, raw text, synopsis, and comments.
/// Also supports optional body preview tabs from PreviewTabStore.
struct RequestInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    let coordinator: MainContentCoordinator
    var previewTabStore: PreviewTabStore
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Request"))
                .font(.system(size: metrics.fontSize, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
            inspectorTabBar
            Divider()
            tabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: previewTabStore.requestTabs.map(\.id)) { _, availableTabIDs in
            selectedPreviewTab = InspectorPreviewSelectionReconciler.retainedSelection(
                selectedPreviewTab,
                availableTabIDs: availableTabIDs
            )
        }
    }

    // MARK: Private

    @State private var selectedTab: RequestInspectorTab = .headers
    @State private var selectedPreviewTab: PreviewTab?

    @State private var showPreviewPopover = false
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var tabDescriptors: [InspectorTabDescriptor] {
        var descriptors: [InspectorTabDescriptor] = RequestInspectorTab.allCases.map { tab in
            InspectorTabDescriptor(
                id: "native.\(tab.rawValue)",
                title: tab.displayName,
                isActive: selectedPreviewTab == nil && selectedTab == tab
            ) {
                selectedPreviewTab = nil
                selectedTab = tab
            }
        }

        for (index, tab) in previewTabStore.requestTabs.enumerated() {
            descriptors.append(
                InspectorTabDescriptor(
                    id: "preview.\(tab.id)",
                    title: tab.name,
                    isActive: selectedPreviewTab == tab,
                    startsNewGroup: index == 0
                ) {
                    selectedPreviewTab = tab
                }
            )
        }

        return descriptors
    }

    private var inspectorTabBar: some View {
        InspectorTabStrip(tabs: tabDescriptors) {
            previewTabMenuButton
        }
    }

    private var previewTabMenuButton: some View {
        Button {
            showPreviewPopover.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: metrics.controlFontSize, weight: .medium))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .frame(width: metrics.inspectorTabHeight, height: metrics.inspectorTabHeight)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Preview Tabs"))
        .popover(isPresented: $showPreviewPopover, arrowEdge: .bottom) {
            PreviewTabPopover(panel: .request, store: previewTabStore)
        }
    }

    @ViewBuilder private var tabContent: some View {
        Group {
            if let previewTab = selectedPreviewTab,
               previewTabStore.requestTabs.contains(where: { $0.id == previewTab.id })
            {
                PreviewTabContentView(
                    tab: previewTab,
                    transaction: transaction,
                    beautify: previewTabStore.autoBeautify
                )
            } else {
                nativeTabContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var nativeTabContent: some View {
        switch selectedTab {
        case .headers:
            requestHeadersView
        case .query:
            QueryInspectorView(transaction: transaction, highlightContext: highlightContext)
        case .body:
            requestBodyView
        case .cookies:
            CookiesInspectorView(transaction: transaction, highlightContext: highlightContext)
        case .raw:
            requestRawView
        case .synopsis:
            SynopsisInspectorView(transaction: transaction)
        case .comments:
            CommentsTabView(coordinator: coordinator, transaction: transaction)
        }
    }

    @ViewBuilder private var requestHeadersView: some View {
        if transaction.request.headers.isEmpty {
            InspectorEmptyStateView(
                String(localized: "No Headers"),
                systemImage: "list.bullet"
            )
        } else {
            ScrollView {
                HeaderKeyValueTable(
                    headers: transaction.request.headers,
                    highlightContext: highlightContext,
                    source: .request,
                    coordinator: coordinator
                )
                    .padding()
            }
        }
    }

    @ViewBuilder private var requestBodyView: some View {
        if let body = transaction.request.body {
            AsyncInspectorTextEditor(
                renderID: "\(transaction.id.uuidString)-request-body-\(body.count)",
                highlightContext: highlightContext
            ) {
                InspectorPayloadFormatter.requestBodyText(body)
            }
        } else {
            InspectorEmptyStateView(
                String(localized: "No Body"),
                systemImage: "doc",
                description: String(localized: "This request has no body")
            )
        }
    }

    private var requestRawView: some View {
        let snapshot = InspectorTransactionSnapshot(transaction: transaction)
        return AsyncInspectorTextEditor(
            renderID: "\(snapshot.id.uuidString)-request-raw-\(snapshot.request.body?.count ?? 0)",
            highlightContext: highlightContext
        ) {
            .text(InspectorPayloadFormatter.rawRequest(snapshot.request))
        }
    }
}
