import SwiftUI

// MARK: - AppearanceSettingsTab

/// Application-wide appearance and readability settings.
struct AppearanceSettingsTab: View {
    // MARK: Internal

    var body: some View {
        SettingsPane {
            SettingsSection(String(localized: "Language", bundle: RockxyLocalization.bundle)) {
                languageSection
            }

            SettingsSection(String(localized: "App UI", bundle: RockxyLocalization.bundle)) {
                appUISection
            }

            SettingsSection(String(localized: "App Theme", bundle: RockxyLocalization.bundle)) {
                themeSection
            }

            restoreDefaultsButton
        }
        .appUIDisplayMetrics(AppUIDisplayMetrics(settings: settingsManager.appUI))
        .font(settingsMetrics.font())
    }

    // MARK: Private

    @State private var hoveredTheme: AppTheme?
    @State private var selectedLanguageID = AppLanguageController.shared.selectedOptionID

    private let settingsManager = AppSettingsManager.shared
    private let languageController = AppLanguageController.shared

    private var appUI: AppUISettings {
        settingsManager.appUI
    }

    private var appTheme: AppTheme {
        settingsManager.appTheme
    }

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: AppUIDisplayMetrics(settings: settingsManager.appUI))
    }

    private var fontSizeBinding: Binding<Int> {
        Binding(
            get: { appUI.fontSize },
            set: { newValue in
                settingsManager.updateAppUI { $0.fontSize = newValue }
            }
        )
    }

    private var tabWidthBinding: Binding<Int> {
        Binding(
            get: { appUI.tabWidth },
            set: { newValue in
                settingsManager.updateAppUI { $0.tabWidth = newValue }
            }
        )
    }

    private var languageSection: some View {
        SettingsFieldRow(String(localized: "App Language:", bundle: RockxyLocalization.bundle)) {
            VStack(alignment: .leading, spacing: 5) {
                Picker("", selection: $selectedLanguageID) {
                    ForEach(languageController.availableOptions) { option in
                        Text(verbatim: languageDisplayName(option))
                            .tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: settingsMetrics.menuWidth(220))
                .onChange(of: selectedLanguageID) { previousValue, newValue in
                    guard previousValue != newValue else {
                        return
                    }
                    if !languageController.select(optionID: newValue) {
                        selectedLanguageID = languageController.selectedOptionID
                    }
                }

                Text(
                    String(
                        localized: "System Default follows your Mac. Choosing another language changes Rockxy immediately.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(settingsMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            selectedLanguageID = languageController.selectedOptionID
        }
    }

    private var appUISection: some View {
        VStack(alignment: .leading, spacing: settingsMetrics.sectionContentSpacing) {
            SettingsFieldRow(String(localized: "Font Size:", bundle: RockxyLocalization.bundle)) {
                Picker("", selection: fontSizeBinding) {
                    ForEach(AppUISettings.allowedFontSizes, id: \.self) { size in
                        Text("\(size)").tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: settingsMetrics.menuWidth(84))
            }

            SettingsFieldRow(String(localized: "Tab Width:", bundle: RockxyLocalization.bundle)) {
                Picker("", selection: tabWidthBinding) {
                    ForEach(AppUISettings.allowedTabWidths, id: \.self) { width in
                        Text(String(localized: "\(width) Spaces", bundle: RockxyLocalization.bundle)).tag(width)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: settingsMetrics.menuWidth(128))
            }

            SettingsIndentedContent {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(
                        String(localized: "Use Monospaced Font", bundle: RockxyLocalization.bundle),
                        isOn: appUIToggle(\.useMonospacedFont)
                    )
                    .toggleStyle(.checkbox)

                    Text(
                        String(
                            localized: "Applies throughout the app, including navigation, controls, tables, and inspectors.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsFieldRow(String(localized: "Body Tab:", bundle: RockxyLocalization.bundle)) {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(
                        String(localized: "Word Wrap", bundle: RockxyLocalization.bundle),
                        isOn: appUIToggle(\.bodyWordWrap)
                    )
                    Toggle(
                        String(localized: "Show Invisibles", bundle: RockxyLocalization.bundle),
                        isOn: appUIToggle(\.bodyShowInvisibles)
                    )
                    Toggle(
                        String(localized: "Show Minimap", bundle: RockxyLocalization.bundle),
                        isOn: appUIToggle(\.bodyShowMinimap)
                    )
                    Toggle(
                        String(localized: "Scroll Beyond The Last Line", bundle: RockxyLocalization.bundle),
                        isOn: appUIToggle(\.bodyScrollBeyondLastLine)
                    )
                }
                .toggleStyle(.checkbox)
            }

            SettingsFieldRow(String(localized: "Other:", bundle: RockxyLocalization.bundle)) {
                Toggle(
                    String(localized: "Alternative Rows Background Colors", bundle: RockxyLocalization.bundle),
                    isOn: appUIToggle(\.useAlternatingRowBackgroundColors)
                )
                .toggleStyle(.checkbox)
            }
        }
        .font(settingsMetrics.font())
    }

    private var themeSection: some View {
        HStack(spacing: max(28, settingsMetrics.sectionSpacing * 2)) {
            ForEach(AppTheme.allCases) { theme in
                themeOption(theme)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var restoreDefaultsButton: some View {
        HStack {
            Spacer()
            Button {
                settingsManager.restoreAppearanceDefaults()
                languageController.select(optionID: AppLanguageOption.systemID)
                selectedLanguageID = languageController.selectedOptionID
            } label: {
                Label(
                    String(localized: "Restore Defaults", bundle: RockxyLocalization.bundle),
                    systemImage: "arrow.clockwise"
                )
            }
            .controlSize(.regular)
        }
        .font(settingsMetrics.font())
    }

    private func themeOption(_ theme: AppTheme) -> some View {
        Button {
            settingsManager.updateAppTheme(theme)
        } label: {
            VStack(spacing: 8) {
                ThemePreviewCard(theme: theme)
                    .frame(width: 78, height: 54)

                HStack(spacing: 6) {
                    if appTheme == theme {
                        Image(systemName: "checkmark.circle.fill")
                            .font(settingsMetrics.font(weight: .semibold))
                            .foregroundStyle(Color(nsColor: .systemGreen))
                    }
                    Text(theme.displayName)
                        .font(settingsMetrics.font())
                        .foregroundStyle(.primary)
                }
                .frame(minWidth: 82)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(themeOptionFill(theme))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        appTheme == theme ? Color.accentColor.opacity(0.55) : Color.clear,
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredTheme = isHovered ? theme : nil
        }
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(appTheme == theme ? [.isButton, .isSelected] : .isButton)
    }

    private func themeOptionFill(_ theme: AppTheme) -> Color {
        if appTheme == theme {
            return Color.accentColor.opacity(0.10)
        }
        if hoveredTheme == theme {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }

    private func appUIToggle(_ keyPath: WritableKeyPath<AppUISettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { appUI[keyPath: keyPath] },
            set: { newValue in
                settingsManager.updateAppUI { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func languageDisplayName(_ option: AppLanguageOption) -> String {
        option.isSystemDefault
            ? String(localized: "System Default", bundle: RockxyLocalization.bundle)
            : option.nativeDisplayName
    }
}

// MARK: - ThemePreviewCard

private struct ThemePreviewCard: View {
    // MARK: Internal

    let theme: AppTheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(background)

            if theme == .system {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(Color(nsColor: .controlBackgroundColor))
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 4) {
                Circle().fill(Color(nsColor: .systemRed))
                Circle().fill(Color(nsColor: .systemYellow))
                Circle().fill(Color(nsColor: .systemGreen))
            }
            .frame(width: 34, height: 6)
            .padding(7)

            if theme != .system {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HTTP/1.1 OK 200")
                        .foregroundStyle(.green)
                    Text("Vary: Origin")
                        .foregroundStyle(.purple)
                    Text("Connection: close")
                        .foregroundStyle(.blue)
                }
                .font(.system(size: 4.5, design: .monospaced))
                .padding(.top, 22)
                .padding(.leading, 11)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    // MARK: Private

    private var background: Color {
        switch theme {
        case .system,
             .light:
            Color(nsColor: .textBackgroundColor)
        case .dark:
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
