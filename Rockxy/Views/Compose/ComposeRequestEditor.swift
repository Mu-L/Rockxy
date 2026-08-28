import SwiftUI

// Renders the compose request editor interface for the compose workflow.

// MARK: - ComposeRequestEditor

/// Left panel of the Compose window. Segmented tabs for Headers, Query, Body, and Raw.
struct ComposeRequestEditor: View {
    // MARK: Internal

    @Bindable var viewModel: ComposeViewModel

    let onLoadFromFile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            Group {
                switch selectedTab {
                case .headers:
                    headersEditor
                case .query:
                    queryEditor
                case .body:
                    bodyEditor
                case .raw:
                    rawView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Private

    @State private var selectedTab: ComposeRequestTab = .headers
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var headerBar: some View {
        HStack(spacing: toolMetrics.headerSpacing) {
            Text(String(localized: "Request"))
                .font(toolMetrics.font(weight: .semibold))

            tabPicker

            Spacer()

            requestMenu
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .frame(minHeight: max(44, toolMetrics.formControlHeight + 16))
    }

    @ViewBuilder private var tabPicker: some View {
        if toolMetrics.bodyFontSize >= 20 {
            Picker(String(localized: "Request Section"), selection: $selectedTab) {
                ForEach(ComposeRequestTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 130)
            .accessibilityLabel(String(localized: "Request section"))
        } else {
            Picker(String(localized: "Request Section"), selection: $selectedTab) {
                ForEach(ComposeRequestTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityLabel(String(localized: "Request section"))
        }
    }

    private var requestMenu: some View {
        Menu {
            Button(String(localized: "Load from File...")) {
                onLoadFromFile()
                selectedTab = .body
            }
            Divider()
            Button(String(localized: "JSON Prettier")) {
                viewModel.prettifyJSONBody()
                selectedTab = .body
            }
            Button(String(localized: "Prettify XML")) {
                viewModel.prettifyXMLBody()
                selectedTab = .body
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
        }
        .menuStyle(.button)
        .help(String(localized: "Request Body Options"))
    }

    // MARK: - Headers Tab

    private var headersEditor: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                columnHeaders(name: "Name", value: "Value")

                ForEach(viewModel.headers) { header in
                    HStack(spacing: 8) {
                        Toggle("", isOn: headerEnabledBinding(for: header.id))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .frame(width: 24)

                        TextField(
                            String(localized: "e.g. Content-Type"),
                            text: headerNameBinding(for: header.id)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(minHeight: toolMetrics.formControlHeight)

                        TextField(
                            String(localized: "e.g. application/json"),
                            text: headerValueBinding(for: header.id)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(minHeight: toolMetrics.formControlHeight)

                        removeButton {
                            viewModel.removeHeader(id: header.id)
                        }
                    }
                    .padding(.vertical, 4)
                }

                addButton(String(localized: "Add Header")) {
                    viewModel.addHeader()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
    }

    // MARK: - Query Tab

    private var queryEditor: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                columnHeaders(name: "Name", value: "Value")

                ForEach(viewModel.queryItems) { item in
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 24)

                        TextField(
                            String(localized: "e.g. page"),
                            text: queryNameBinding(for: item.id)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(minHeight: toolMetrics.formControlHeight)

                        TextField(
                            String(localized: "e.g. 1"),
                            text: queryValueBinding(for: item.id)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(minHeight: toolMetrics.formControlHeight)

                        removeButton {
                            viewModel.removeQueryItem(id: item.id)
                        }
                    }
                    .padding(.vertical, 4)
                }

                addButton(String(localized: "Add Parameter")) {
                    viewModel.addQueryItem()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
        }
    }

    // MARK: - Body Tab

    private var bodyEditor: some View {
        VStack(spacing: 0) {
            TextEditor(text: bodyBinding)
                .font(toolMetrics.font(monospaced: true))
                .padding(8)

            if let message = viewModel.lastFormattingError {
                Divider()
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Raw Tab

    private var rawView: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(viewModel.rawRequestText)
                .font(toolMetrics.font(monospaced: true))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    // MARK: - Shared Helpers

    private func columnHeaders(name: LocalizedStringResource, value: LocalizedStringResource) -> some View {
        HStack {
            Color.clear.frame(width: 24)
            Text(name)
                .font(toolMetrics.tableHeaderFont())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(toolMetrics.tableHeaderFont())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 24)
        }
        .padding(.bottom, 4)
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .frame(width: 24)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Remove"))
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Button(action: action) {
                Label(title, systemImage: "plus.circle")
                    .font(toolMetrics.secondaryFont())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: - Bindings

    private var bodyBinding: Binding<String> {
        Binding(
            get: { viewModel.body },
            set: { viewModel.replaceUnavailableBody(with: $0) }
        )
    }

    private func headerEnabledBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { viewModel.headers.first(where: { $0.id == id })?.isEnabled ?? true },
            set: { newValue in
                if let idx = viewModel.headers.firstIndex(where: { $0.id == id }) {
                    viewModel.headers[idx].isEnabled = newValue
                }
            }
        )
    }

    private func headerNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.headers.first(where: { $0.id == id })?.name ?? "" },
            set: { newValue in
                if let idx = viewModel.headers.firstIndex(where: { $0.id == id }) {
                    viewModel.headers[idx].name = newValue
                }
            }
        )
    }

    private func headerValueBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.headers.first(where: { $0.id == id })?.value ?? "" },
            set: { newValue in
                if let idx = viewModel.headers.firstIndex(where: { $0.id == id }) {
                    viewModel.headers[idx].value = newValue
                }
            }
        )
    }

    private func queryNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.queryItems.first(where: { $0.id == id })?.name ?? "" },
            set: { newValue in
                if let idx = viewModel.queryItems.firstIndex(where: { $0.id == id }) {
                    viewModel.queryItems[idx].name = newValue
                    viewModel.syncQueryToURL()
                }
            }
        )
    }

    private func queryValueBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.queryItems.first(where: { $0.id == id })?.value ?? "" },
            set: { newValue in
                if let idx = viewModel.queryItems.firstIndex(where: { $0.id == id }) {
                    viewModel.queryItems[idx].value = newValue
                    viewModel.syncQueryToURL()
                }
            }
        )
    }
}

// MARK: - ComposeRequestTab

private enum ComposeRequestTab: String, CaseIterable, Identifiable {
    case headers
    case query
    case body
    case raw

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .headers: String(localized: "Header")
        case .query: String(localized: "Query")
        case .body: String(localized: "Body")
        case .raw: String(localized: "Raw")
        }
    }
}
