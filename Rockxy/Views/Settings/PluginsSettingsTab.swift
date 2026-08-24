import SwiftUI

// Renders the plugins settings interface for the settings experience.

// MARK: - PluginsSettingsTab

struct PluginsSettingsTab: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                pluginListPanel
                    .frame(
                        minWidth: settingsMetrics.fieldWidth(220),
                        idealWidth: settingsMetrics.fieldWidth(250),
                        maxWidth: settingsMetrics.fieldWidth(300)
                    )

                if let plugin = viewModel.selectedPlugin {
                    PluginDetailView(plugin: plugin, viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            bottomBar
        }
        .font(settingsMetrics.font())
        .task { await viewModel.loadPlugins() }
        .alert(
            String(localized: "Plugin Error"),
            isPresented: Binding(
                get: { viewModel.lastEnableError != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.lastEnableError = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK")) { viewModel.lastEnableError = nil }
        } message: {
            Text(viewModel.lastEnableError ?? "")
        }
    }

    // MARK: Private

    @State private var viewModel = PluginSettingsViewModel()
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private var pluginListPanel: some View {
        VStack(spacing: 0) {
            TextField(String(localized: "Search Plugins"), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .font(settingsMetrics.font())
                .frame(minHeight: settingsMetrics.controlHeight)
                .padding(8)

            Divider()

            categoryFilterBar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            Divider()

            List(viewModel.filteredPlugins, selection: $viewModel.selectedPluginID) { plugin in
                PluginListRow(
                    plugin: plugin,
                    isSelected: viewModel.selectedPluginID == plugin.id
                ) { _ in
                    Task { await viewModel.togglePlugin(id: plugin.id) }
                }
                .tag(plugin.id)
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.inset)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var categoryFilterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                categoryPill(String(localized: "All"), category: nil)
                categoryPill(String(localized: "Inspector"), category: .inspector)
                categoryPill(String(localized: "Exporter"), category: .exporter)
                categoryPill(String(localized: "Script"), category: .script)
            }

            Picker(String(localized: "Plugin Category"), selection: $viewModel.selectedCategory) {
                Text(String(localized: "All")).tag(PluginType?.none)
                Text(String(localized: "Inspector")).tag(PluginType?.some(.inspector))
                Text(String(localized: "Exporter")).tag(PluginType?.some(.exporter))
                Text(String(localized: "Script")).tag(PluginType?.some(.script))
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No Plugin Selected"), systemImage: "puzzlepiece.extension")
        } description: {
            Text("Select a plugin from the list to view its details and configuration.")
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.openPluginsFolder()
            } label: {
                Label(String(localized: "Open Plugins Folder"), systemImage: "folder")
            }

            Button {
                viewModel.installFromFile()
            } label: {
                Label(String(localized: "Install from File…"), systemImage: "plus")
            }

            Spacer()

            Text(String(localized: "\(viewModel.plugins.count) plugins"))
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: settingsMetrics.footerHeight)
        .rockxyFunctionalBar()
    }

    private func categoryPill(_ title: String, category: PluginType?) -> some View {
        let isActive = viewModel.selectedCategory == category
        return Button {
            viewModel.selectedCategory = category
        } label: {
            Text(title)
                .font(settingsMetrics.secondaryFont(weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .rockxyChipStyle(
                    tint: .accentColor,
                    isActive: isActive,
                    isEnabled: true
                )
        }
        .buttonStyle(.plain)
    }
}
