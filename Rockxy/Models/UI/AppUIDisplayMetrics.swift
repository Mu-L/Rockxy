import AppKit
import SwiftUI

// MARK: - AppUIDisplayMetrics

struct AppUIDisplayMetrics: Equatable {
    let settings: AppUISettings

    init(settings: AppUISettings = .default) {
        self.settings = settings
    }

    var fontSize: CGFloat {
        CGFloat(settings.fontSize)
    }

    var primaryFontSize: CGFloat {
        fontSize
    }

    var controlFontSize: CGFloat {
        max(11, fontSize)
    }

    var secondaryFontSize: CGFloat {
        max(9, fontSize - 1)
    }

    var metadataFontSize: CGFloat {
        max(10, fontSize - 2)
    }

    var badgeFontSize: CGFloat {
        max(10, fontSize - 3)
    }

    var monospacedContentFontSize: CGFloat {
        fontSize
    }

    var sidebarNavigationFontSize: CGFloat {
        max(11, fontSize)
    }

    var sidebarSecondaryFontSize: CGFloat {
        max(10, fontSize - 1)
    }

    var sidebarSectionHeaderFontSize: CGFloat {
        max(10, fontSize - 2)
    }

    var sidebarBadgeFontSize: CGFloat {
        max(10, fontSize - 2)
    }

    var sidebarIconFontSize: CGFloat {
        max(12, fontSize)
    }

    var sidebarAppIconSize: CGFloat {
        max(20, min(fontSize + 7, 32))
    }

    var sidebarRowHeight: CGFloat {
        max(24, fontSize + 12)
    }

    var tableStatusDotSize: CGFloat {
        max(8, min(fontSize - 3, 12))
    }

    var tableSSLIconSize: CGFloat {
        max(10, min(fontSize - 1, 16))
    }

    var tableClientIconSize: CGFloat {
        max(14, min(fontSize + 3, 18))
    }

    var chromeFontSize: CGFloat {
        controlFontSize
    }

    var chromeSecondaryFontSize: CGFloat {
        secondaryFontSize
    }

    var chromeIconFontSize: CGFloat {
        max(11, controlFontSize)
    }

    var chromeBadgeFontSize: CGFloat {
        max(10, controlFontSize)
    }

    var chromeStatusDotSize: CGFloat {
        max(8, min(controlFontSize - 2, 14))
    }

    var chromeControlHeight: CGFloat {
        max(32, controlFontSize + 16)
    }

    var chromeBadgeHeight: CGFloat {
        max(24, controlFontSize + 11)
    }

    var workspaceTabFontSize: CGFloat {
        max(13, min(controlFontSize, 18))
    }

    var tableRowHeight: CGFloat {
        if fontSize <= 12 {
            return max(24, fontSize + 16)
        }
        if fontSize <= 13 {
            return 28
        }
        return fontSize + 16
    }

    var tableTextHeight: CGFloat {
        max(17, fontSize + 5)
    }

    var statusBarHeight: CGFloat {
        max(34, fontSize + 22)
    }

    var filterBarHeight: CGFloat {
        max(26, fontSize + 14)
    }

    var inspectorTabHeight: CGFloat {
        max(22, fontSize + 10)
    }

    var inspectorTextEditorSettings: InspectorTextEditorSettings {
        InspectorTextEditorSettings(appUI: settings)
    }

    var appKitBodyFont: NSFont {
        settings.useMonospacedFont
            ? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : .systemFont(ofSize: fontSize, weight: .regular)
    }

    var appKitMonospacedFont: NSFont {
        .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    func appKitFont(weight: NSFont.Weight = .regular, monospaced: Bool = false) -> NSFont {
        if monospaced || settings.useMonospacedFont {
            return .monospacedSystemFont(ofSize: fontSize, weight: weight)
        }
        return .systemFont(ofSize: fontSize, weight: weight)
    }

    func swiftUIFont(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        swiftUIFont(size: fontSize, weight: weight, monospaced: monospaced)
    }

    func swiftUIFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        monospaced: Bool = false
    ) -> Font {
        if monospaced || settings.useMonospacedFont {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .system(size: size, weight: weight)
    }
}

// MARK: - BottomInspectorLayoutMetrics

/// Font-aware minimum heights for the request-list / bottom-inspector split.
///
/// Pure and value-typed so the sizing can be verified without a live window. Both minima are
/// derived from `AppUIDisplayMetrics` so the split tracks the Rockxy app font size instead of
/// pinning fixed point values.
struct BottomInspectorLayoutMetrics: Equatable {
    // MARK: Lifecycle

    init(appMetrics: AppUIDisplayMetrics = AppUIDisplayMetrics()) {
        self.appMetrics = appMetrics
    }

    // MARK: Internal

    let appMetrics: AppUIDisplayMetrics

    /// Minimum height that keeps roughly six request rows plus the compact table header and
    /// surrounding chrome visible. ≈200pt at the default 13pt app font, scaling up with it.
    var requestListMinimumHeight: CGFloat {
        let rowHeight = appMetrics.tableRowHeight
        let rows = rowHeight * Self.visibleRequestRows
        let header = rowHeight
        return (rows + header + Self.requestChromeInset).rounded()
    }

    /// Minimum height for a compact, native inspector: the tab strip plus a readable stack of
    /// content lines and vertical chrome. ≈232pt at 13pt, scaling up for larger app fonts.
    var inspectorMinimumHeight: CGFloat {
        let tabStrip = appMetrics.inspectorTabHeight
        let contentLines = appMetrics.tableTextHeight * Self.inspectorVisibleLines
        return (tabStrip + contentLines + Self.inspectorChromeInset).rounded()
    }

    // MARK: Private

    private static let visibleRequestRows: CGFloat = 6
    private static let requestChromeInset: CGFloat = 4
    private static let inspectorVisibleLines: CGFloat = 10
    private static let inspectorChromeInset: CGFloat = 29
}

// MARK: - DeveloperSetupDisplayMetrics

struct DeveloperSetupDisplayMetrics: Equatable {
    let appMetrics: AppUIDisplayMetrics

    init(appMetrics: AppUIDisplayMetrics = AppUIDisplayMetrics()) {
        self.appMetrics = appMetrics
    }

    var titleFontSize: CGFloat {
        max(15, appMetrics.primaryFontSize + 5)
    }

    var sectionTitleFontSize: CGFloat {
        max(13, appMetrics.primaryFontSize + 1)
    }

    var bodyFontSize: CGFloat {
        appMetrics.primaryFontSize
    }

    var controlFontSize: CGFloat {
        appMetrics.controlFontSize
    }

    var secondaryFontSize: CGFloat {
        max(11, appMetrics.primaryFontSize - 1)
    }

    var metadataFontSize: CGFloat {
        appMetrics.metadataFontSize
    }

    var badgeFontSize: CGFloat {
        appMetrics.badgeFontSize
    }

    var iconFontSize: CGFloat {
        max(13, appMetrics.controlFontSize + 1)
    }

    var prominentIconFontSize: CGFloat {
        max(20, appMetrics.primaryFontSize + 9)
    }

    var snippetFontSize: CGFloat {
        appMetrics.monospacedContentFontSize
    }

    var sidebarRowHeight: CGFloat {
        max(36, appMetrics.primaryFontSize + 24)
    }

    var cardMinimumHeight: CGFloat {
        max(82, appMetrics.primaryFontSize + 68)
    }

    func font(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        font(size: bodyFontSize, weight: weight, monospaced: monospaced)
    }

    func secondaryFont(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        font(size: secondaryFontSize, weight: weight, monospaced: monospaced)
    }

    /// Size-parameterized font that honors the Rockxy font-family preference
    /// (`useMonospacedFont`) so every Developer Setup label scales and switches
    /// family consistently. Snippet/code text should pass `monospaced: true`.
    func font(size: CGFloat, weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        if monospaced || appMetrics.settings.useMonospacedFont {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .system(size: size, weight: weight)
    }
}

// MARK: - ToolWindowDisplayMetrics

struct ToolWindowDisplayMetrics: Equatable {
    let appMetrics: AppUIDisplayMetrics

    init(appMetrics: AppUIDisplayMetrics = AppUIDisplayMetrics()) {
        self.appMetrics = appMetrics
    }

    var bodyFontSize: CGFloat {
        appMetrics.primaryFontSize
    }

    var secondaryFontSize: CGFloat {
        max(10, appMetrics.primaryFontSize - 1)
    }

    var metadataFontSize: CGFloat {
        max(10, appMetrics.primaryFontSize - 2)
    }

    var tableHeaderFontSize: CGFloat {
        max(12, appMetrics.primaryFontSize - 1)
    }

    var tableRowHeight: CGFloat {
        max(28, appMetrics.primaryFontSize + 15)
    }

    var shortcutFontSize: CGFloat {
        secondaryFontSize
    }

    var footerControlHeight: CGFloat {
        max(26, appMetrics.primaryFontSize + 13)
    }

    var compactButtonSize: CGFloat {
        max(23, appMetrics.primaryFontSize + 10)
    }

    var compactIconFontSize: CGFloat {
        max(12, appMetrics.primaryFontSize)
    }

    var smallIconFontSize: CGFloat {
        max(10, appMetrics.primaryFontSize - 3)
    }

    var emptyStateFontSize: CGFloat {
        bodyFontSize
    }

    var contentHorizontalPadding: CGFloat {
        18
    }

    var headerTopPadding: CGFloat {
        16
    }

    var headerBottomPadding: CGFloat {
        10
    }

    var headerSpacing: CGFloat {
        10
    }

    var controlSpacing: CGFloat {
        8
    }

    var shortcutTopPadding: CGFloat {
        8
    }

    var shortcutBottomPadding: CGFloat {
        4
    }

    var footerTopPadding: CGFloat {
        8
    }

    var footerBottomPadding: CGFloat {
        14
    }

    var tableCellHorizontalPadding: CGFloat {
        12
    }

    var formHorizontalPadding: CGFloat {
        18
    }

    var formVerticalPadding: CGFloat {
        12
    }

    var formRowSpacing: CGFloat {
        9
    }

    var formLabelWidth: CGFloat {
        110
    }

    var formCompactLabelWidth: CGFloat {
        92
    }

    var formWideLabelWidth: CGFloat {
        150
    }

    var formControlHeight: CGFloat {
        max(24, bodyFontSize + 12)
    }

    var codeEditorSettings: InspectorTextEditorSettings {
        InspectorTextEditorSettings(
            fontSize: Int(appMetrics.primaryFontSize),
            tabWidth: appMetrics.settings.tabWidth,
            useMonospacedFont: true,
            wordWrap: false
        )
    }

    var footerButtonWidth: CGFloat {
        max(100, bodyFontSize + 88)
    }

    func menuWidth(_ baseWidth: CGFloat) -> CGFloat {
        baseWidth
    }

    func fieldWidth(_ baseWidth: CGFloat) -> CGFloat {
        baseWidth
    }

    func font(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        if monospaced || appMetrics.settings.useMonospacedFont {
            return .system(size: bodyFontSize, weight: weight, design: .monospaced)
        }
        return .system(size: bodyFontSize, weight: weight)
    }

    func secondaryFont(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        if monospaced || appMetrics.settings.useMonospacedFont {
            return .system(size: secondaryFontSize, weight: weight, design: .monospaced)
        }
        return .system(size: secondaryFontSize, weight: weight)
    }

    func metadataFont(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        if monospaced || appMetrics.settings.useMonospacedFont {
            return .system(size: metadataFontSize, weight: weight, design: .monospaced)
        }
        return .system(size: metadataFontSize, weight: weight)
    }

    func tableHeaderFont(weight: Font.Weight = .medium) -> Font {
        .system(size: tableHeaderFontSize, weight: weight)
    }
}

// MARK: - SettingsDisplayMetrics

struct SettingsDisplayMetrics: Equatable {
    var appMetrics: AppUIDisplayMetrics

    var bodyFontSize: CGFloat {
        appMetrics.primaryFontSize
    }

    var secondaryFontSize: CGFloat {
        max(10, appMetrics.primaryFontSize - 1)
    }

    var metadataFontSize: CGFloat {
        max(10, appMetrics.primaryFontSize - 2)
    }

    // MARK: Window geometry (adaptive)

    // The Settings window is a resizable sidebar/content shell, not a pinned card.
    // Geometry grows with the Rockxy font size so the nine categories and their
    // panes stay usable at 13 / 20 / 28pt without clipping or forcing a tiny sidebar.

    var sidebarMinWidth: CGFloat {
        max(196, bodyFontSize * 6 + 118)
    }

    var sidebarIdealWidth: CGFloat {
        sidebarMinWidth
    }

    var sidebarMaxWidth: CGFloat {
        sidebarMinWidth + 96
    }

    var contentMinWidth: CGFloat {
        // Accommodates the widest shared label + 420pt field row, section
        // insets, and the standalone 640pt GitHub guidance block.
        max(700, labelWidth + 16 + 420 + contentPadding * 2 + 24)
    }

    var windowMinWidth: CGFloat {
        sidebarMinWidth + contentMinWidth
    }

    var windowIdealWidth: CGFloat {
        windowMinWidth + 132
    }

    var windowMinHeight: CGFloat {
        // Panes scroll vertically, so the minimum stays usable on compact
        // displays even when Rockxy's app font is set to 28pt.
        max(500, bodyFontSize * 6 + 382)
    }

    var windowIdealHeight: CGFloat {
        windowMinHeight + 96
    }

    // MARK: Content density

    var sectionSpacing: CGFloat {
        18
    }

    var sectionContentSpacing: CGFloat {
        14
    }

    var paneHeaderSpacing: CGFloat {
        4
    }

    var paneContentPadding: CGFloat {
        20
    }

    var contentPadding: CGFloat {
        28
    }

    var labelWidth: CGFloat {
        max(160, bodyFontSize * 8 + 56)
    }

    var wideLabelWidth: CGFloat {
        labelWidth + 22
    }

    var rowLeading: CGFloat {
        labelWidth + 16
    }

    var controlHeight: CGFloat {
        max(24, bodyFontSize + 12)
    }

    var footerHeight: CGFloat {
        max(36, bodyFontSize + 24)
    }

    func fieldWidth(_ baseWidth: CGFloat) -> CGFloat {
        baseWidth
    }

    func menuWidth(_ baseWidth: CGFloat) -> CGFloat {
        baseWidth
    }

    func font(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        if monospaced || appMetrics.settings.useMonospacedFont {
            return .system(size: bodyFontSize, weight: weight, design: .monospaced)
        }
        return .system(size: bodyFontSize, weight: weight)
    }

    func secondaryFont(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        if monospaced || appMetrics.settings.useMonospacedFont {
            return .system(size: secondaryFontSize, weight: weight, design: .monospaced)
        }
        return .system(size: secondaryFontSize, weight: weight)
    }

    func metadataFont(weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        if monospaced || appMetrics.settings.useMonospacedFont {
            return .system(size: metadataFontSize, weight: weight, design: .monospaced)
        }
        return .system(size: metadataFontSize, weight: weight)
    }
}

// MARK: - InspectorTextEditorSettings

struct InspectorTextEditorSettings: Equatable, Sendable {
    var fontSize: Int = AppUISettings.defaultFontSize
    var tabWidth: Int = AppUISettings.defaultTabWidth
    var useMonospacedFont = false
    var wordWrap = true
    var showInvisibles = false
    var showMinimap = false
    var scrollBeyondLastLine = false

    init(
        fontSize: Int = AppUISettings.defaultFontSize,
        tabWidth: Int = AppUISettings.defaultTabWidth,
        useMonospacedFont: Bool = false,
        wordWrap: Bool = true,
        showInvisibles: Bool = false,
        showMinimap: Bool = false,
        scrollBeyondLastLine: Bool = false
    ) {
        self.fontSize = AppUISettings.validFontSize(fontSize)
        self.tabWidth = AppUISettings.validTabWidth(tabWidth)
        self.useMonospacedFont = useMonospacedFont
        self.wordWrap = wordWrap
        self.showInvisibles = showInvisibles
        self.showMinimap = showMinimap
        self.scrollBeyondLastLine = scrollBeyondLastLine
    }

    init(appUI: AppUISettings) {
        self.init(
            fontSize: appUI.fontSize,
            tabWidth: appUI.tabWidth,
            useMonospacedFont: appUI.useMonospacedFont,
            wordWrap: appUI.bodyWordWrap,
            showInvisibles: appUI.bodyShowInvisibles,
            showMinimap: appUI.bodyShowMinimap,
            scrollBeyondLastLine: appUI.bodyScrollBeyondLastLine
        )
    }

    var cgFontSize: CGFloat {
        CGFloat(fontSize)
    }

    var appKitFont: NSFont {
        useMonospacedFont
            ? .monospacedSystemFont(ofSize: cgFontSize, weight: .regular)
            : .systemFont(ofSize: cgFontSize, weight: .regular)
    }

    var tabInterval: CGFloat {
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: appKitFont]).width
        return max(1, spaceWidth * CGFloat(tabWidth))
    }
}

// MARK: - AppUIDisplayMetricsKey

private struct AppUIDisplayMetricsKey: EnvironmentKey {
    static let defaultValue = AppUIDisplayMetrics()
}

extension EnvironmentValues {
    var appUIDisplayMetrics: AppUIDisplayMetrics {
        get { self[AppUIDisplayMetricsKey.self] }
        set { self[AppUIDisplayMetricsKey.self] = newValue }
    }
}

extension View {
    func appUIDisplayMetrics(_ metrics: AppUIDisplayMetrics) -> some View {
        environment(\.appUIDisplayMetrics, metrics)
    }
}

// MARK: - AppUIDisplayMetricsProvider

struct AppUIDisplayMetricsProvider<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .appUIDisplayMetrics(AppUIDisplayMetrics(settings: settingsManager.appUI))
    }

    private let settingsManager = AppSettingsManager.shared
}

// MARK: - ToolWindowDisplayMetricsProvider

struct ToolWindowDisplayMetricsProvider<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        AppUIDisplayMetricsProvider {
            ToolWindowReadableContent {
                content
            }
        }
    }
}

private struct ToolWindowReadableContent<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .font(toolMetrics.font())
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
