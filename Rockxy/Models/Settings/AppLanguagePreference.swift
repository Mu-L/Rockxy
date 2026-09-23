import Foundation
import Observation

// MARK: - AppLanguageOption

/// A language Rockxy can load from its application bundle.
///
/// Displaying each language in its own language keeps the picker usable even
/// when the currently selected localization is unfamiliar to the user.
struct AppLanguageOption: Identifiable, Hashable, Sendable {
    static let systemID = "system"

    let id: String

    var isSystemDefault: Bool {
        id == Self.systemID
    }

    var nativeDisplayName: String {
        guard !isSystemDefault else {
            return ""
        }
        let locale = Locale(identifier: id)
        return locale.localizedString(forIdentifier: id) ?? id
    }
}

// MARK: - AppLanguageRuntimeState

private struct AppLanguageRuntimeState {
    let bundle: Bundle
    let locale: Locale
}

// MARK: - AppLanguagePreference

/// Persists and resolves Rockxy's app-language preference.
///
/// The language list comes from the app bundle so newly shipped community
/// localizations become available without another hardcoded UI change.
enum AppLanguagePreference {
    // MARK: Internal

    static let defaultsKey = RockxyIdentity.current.defaultsKey("appLanguage")
    static let appleLanguagesDefaultsKey = "AppleLanguages"

    static func availableOptions(
        localizations: [String] = Bundle.main.localizations,
        displayLocale: Locale = .current
    )
        -> [AppLanguageOption]
    {
        let identifiers = supportedIdentifiers(from: localizations)
            .sorted { lhs, rhs in
                let lhsName = displayLocale.localizedString(forIdentifier: lhs) ?? lhs
                let rhsName = displayLocale.localizedString(forIdentifier: rhs) ?? rhs
                let comparison = lhsName.localizedCaseInsensitiveCompare(rhsName)
                return comparison == .orderedSame ? lhs < rhs : comparison == .orderedAscending
            }
        return [AppLanguageOption(id: AppLanguageOption.systemID)]
            + identifiers.map(AppLanguageOption.init(id:))
    }

    static func selectedOptionID(
        defaults: UserDefaults = .standard,
        defaultsKey: String = defaultsKey,
        availableLocalizations: [String] = Bundle.main.localizations
    )
        -> String
    {
        guard let identifier = defaults.string(forKey: defaultsKey),
              supportedIdentifiers(from: availableLocalizations).contains(identifier) else
        {
            return AppLanguageOption.systemID
        }
        return identifier
    }

    static func resolvedLocalizationID(
        optionID: String,
        availableLocalizations: [String],
        preferredLanguages: [String]? = nil
    )
        -> String?
    {
        let supported = supportedIdentifiers(from: availableLocalizations)
        guard !supported.isEmpty else {
            return nil
        }
        let preferences = optionID == AppLanguageOption.systemID
            ? preferredLanguages
            : [optionID]
        return Bundle.preferredLocalizations(
            from: supported,
            forPreferences: preferences
        ).first
    }

    /// Returns the Mac's global language order instead of the process-effective
    /// order, which may still contain a per-app `AppleLanguages` override from
    /// an earlier language choice.
    static func systemPreferredLanguages(defaults: UserDefaults = .standard) -> [String] {
        if let languages = defaults.persistentDomain(forName: UserDefaults.globalDomain)?[appleLanguagesDefaultsKey]
            as? [String],
            !languages.isEmpty
        {
            return languages
        }
        return Locale.preferredLanguages
    }

    @discardableResult
    static func apply(
        optionID: String,
        defaults: UserDefaults = .standard,
        defaultsKey: String = defaultsKey,
        availableLocalizations: [String] = Bundle.main.localizations
    )
        -> Bool
    {
        if optionID == AppLanguageOption.systemID {
            defaults.removeObject(forKey: defaultsKey)
            // Selecting System Default is an explicit request to stop using an
            // app-specific language. Remove any legacy/per-app override so the
            // next launch agrees with the live runtime selection as well.
            defaults.removeObject(forKey: appleLanguagesDefaultsKey)
            return true
        }

        guard supportedIdentifiers(from: availableLocalizations).contains(optionID) else {
            return false
        }
        defaults.set(optionID, forKey: defaultsKey)
        return true
    }

    // MARK: Fileprivate

    fileprivate static func runtimeState(
        optionID: String,
        bundle: Bundle,
        systemPreferredLanguages: [String]
    )
        -> AppLanguageRuntimeState
    {
        let identifier = resolvedLocalizationID(
            optionID: optionID,
            availableLocalizations: bundle.localizations,
            preferredLanguages: systemPreferredLanguages
        ) ?? bundle.developmentLocalization ?? "en"
        let localizedBundle = bundle.path(forResource: identifier, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? bundle
        // System Default keeps following the Mac's full, live locale. An explicit choice
        // changes the language only, as macOS does for a per-app language: region formats
        // stay the Mac's.
        let locale = optionID == AppLanguageOption.systemID
            ? Locale.autoupdatingCurrent
            : formattingLocale(languageIdentifier: identifier, regionalBase: .autoupdatingCurrent)
        return AppLanguageRuntimeState(
            bundle: localizedBundle,
            locale: locale
        )
    }

    /// The locale for an explicitly chosen app language.
    ///
    /// Rockxy's Language setting changes the language, never the formats: numbers, times, and
    /// dates keep the Mac's region, 24-hour clock, first weekday, and measurement system, the same
    /// split macOS applies to a per-app language in System Settings. A bare `Locale(identifier:)`
    /// would switch a Mac set to Vietnam from "1.234,5" to "1,234.5" and from a 24-hour clock to
    /// "9:13 PM" just because the interface language changed. The region travels as an `rg`
    /// override, so words inside a format (AM/PM, "5 minutes ago") still follow the language.
    static func formattingLocale(languageIdentifier: String, regionalBase: Locale) -> Locale {
        var components = Locale.Components(identifier: languageIdentifier)
        if let region = regionalBase.region {
            components.region = region
        }
        components.hourCycle = regionalBase.hourCycle
        components.firstDayOfWeek = regionalBase.firstDayOfWeek
        components.measurementSystem = regionalBase.measurementSystem
        return Locale(components: components)
    }

    // MARK: Private

    private static func supportedIdentifiers(from localizations: [String]) -> [String] {
        Array(Set(localizations.filter { !$0.isEmpty && $0.caseInsensitiveCompare("Base") != .orderedSame }))
    }
}

// MARK: - AppLanguageController

/// Owns the runtime-selected string bundle and notifies SwiftUI when it changes.
/// Bundle reads may also occur while background services build user-facing
/// messages, so the resolved runtime state is protected independently of the
/// main-thread preference mutation.
@Observable
final class AppLanguageController: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        defaultsKey: String = AppLanguagePreference.defaultsKey,
        systemPreferredLanguages: [String]? = nil
    ) {
        self.defaults = defaults
        self.mainBundle = bundle
        self.defaultsKey = defaultsKey
        systemPreferredLanguagesOverride = systemPreferredLanguages
        let optionID = AppLanguagePreference.selectedOptionID(
            defaults: defaults,
            defaultsKey: defaultsKey,
            availableLocalizations: bundle.localizations
        )
        selectedOptionID = optionID
        runtimeState = AppLanguagePreference.runtimeState(
            optionID: optionID,
            bundle: bundle,
            systemPreferredLanguages: systemPreferredLanguages
                ?? AppLanguagePreference.systemPreferredLanguages(defaults: defaults)
        )
    }

    // MARK: Internal

    static let shared = AppLanguageController()

    private(set) var selectedOptionID: String

    var availableOptions: [AppLanguageOption] {
        AppLanguagePreference.availableOptions(localizations: mainBundle.localizations)
    }

    var localizedBundle: Bundle {
        observeSelectionOnMainThread()
        return withRuntimeState { $0.bundle }
    }

    var locale: Locale {
        observeSelectionOnMainThread()
        return withRuntimeState { $0.locale }
    }

    @MainActor
    @discardableResult
    func select(optionID: String) -> Bool {
        guard AppLanguagePreference.apply(
            optionID: optionID,
            defaults: defaults,
            defaultsKey: defaultsKey,
            availableLocalizations: mainBundle.localizations
        ) else {
            return false
        }
        guard optionID != selectedOptionID else {
            return true
        }

        let newState = AppLanguagePreference.runtimeState(
            optionID: optionID,
            bundle: mainBundle,
            systemPreferredLanguages: systemPreferredLanguagesOverride
                ?? AppLanguagePreference.systemPreferredLanguages(defaults: defaults)
        )
        runtimeStateLock.lock()
        runtimeState = newState
        runtimeStateLock.unlock()
        selectedOptionID = optionID
        return true
    }

    // MARK: Private

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let mainBundle: Bundle
    @ObservationIgnored private let defaultsKey: String
    @ObservationIgnored private let systemPreferredLanguagesOverride: [String]?
    @ObservationIgnored private let runtimeStateLock = NSLock()
    @ObservationIgnored private var runtimeState: AppLanguageRuntimeState

    private func observeSelectionOnMainThread() {
        if Thread.isMainThread {
            _ = selectedOptionID
        }
    }

    private func withRuntimeState<Result>(_ operation: (AppLanguageRuntimeState) -> Result) -> Result {
        runtimeStateLock.lock()
        defer { runtimeStateLock.unlock() }
        return operation(runtimeState)
    }
}

// MARK: - RockxyLocalization

/// Runtime localization values used by string-catalog lookups and SwiftUI.
enum RockxyLocalization {
    static var bundle: Bundle {
        AppLanguageController.shared.localizedBundle
    }

    static var locale: Locale {
        AppLanguageController.shared.locale
    }
}
