import Foundation
@testable import Rockxy
import Testing

// MARK: - AppLanguagePreferenceTests

struct AppLanguagePreferenceTests {
    @Test("Available languages come from the app bundle and keep System Default first")
    func availableLanguagesAreBundleDriven() {
        let options = AppLanguagePreference.availableOptions(
            localizations: ["zh-Hans", "Base", "en", "fr", "en"],
            displayLocale: Locale(identifier: "en")
        )

        #expect(options.first?.id == AppLanguageOption.systemID)
        #expect(Set(options.dropFirst().map(\.id)) == ["en", "fr", "zh-Hans"])
        #expect(options.count == 4)
        #expect(options.dropFirst().allSatisfy { !$0.nativeDisplayName.isEmpty })
    }

    @Test("Language identifiers use Bundle fallback matching")
    func languageIdentifiersUseBundleFallbackMatching() {
        let available = ["en", "zh-Hans"]

        #expect(AppLanguagePreference.resolvedLocalizationID(
            optionID: AppLanguageOption.systemID,
            availableLocalizations: available,
            preferredLanguages: ["zh-CN"]
        ) == "zh-Hans")
        #expect(AppLanguagePreference.resolvedLocalizationID(
            optionID: "en-GB",
            availableLocalizations: available
        ) == "en")
    }

    @Test("Applying a language writes and removes Rockxy's app preference")
    func applyingLanguagePersistsAppPreference() throws {
        let suiteName = "AppLanguagePreferenceTests.\(UUID().uuidString)"
        let defaultsKey = "selectedLanguage"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppLanguagePreference.apply(
            optionID: "zh-Hans",
            defaults: defaults,
            defaultsKey: defaultsKey,
            availableLocalizations: ["en", "zh-Hans"]
        ))
        #expect(defaults.string(forKey: defaultsKey) == "zh-Hans")
        #expect(AppLanguagePreference.selectedOptionID(
            defaults: defaults,
            defaultsKey: defaultsKey,
            availableLocalizations: ["en", "zh-Hans"]
        ) == "zh-Hans")

        #expect(AppLanguagePreference.apply(
            optionID: AppLanguageOption.systemID,
            defaults: defaults,
            defaultsKey: defaultsKey,
            availableLocalizations: ["en", "zh-Hans"]
        ))
        #expect(defaults.object(forKey: defaultsKey) == nil)
    }

    @Test("Unsupported language identifiers are rejected without replacing the current choice")
    func unsupportedLanguageIsRejected() throws {
        let suiteName = "AppLanguagePreferenceTests.\(UUID().uuidString)"
        let defaultsKey = "selectedLanguage"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("en", forKey: defaultsKey)

        #expect(!AppLanguagePreference.apply(
            optionID: "de",
            defaults: defaults,
            defaultsKey: defaultsKey,
            availableLocalizations: ["en", "zh-Hans"]
        ))
        #expect(defaults.string(forKey: defaultsKey) == "en")
    }

    @MainActor
    @Test("The runtime controller changes string catalogs without relaunching the app")
    func runtimeControllerChangesLanguageImmediately() throws {
        let suiteName = "AppLanguagePreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = AppLanguageController(
            defaults: defaults,
            bundle: .main,
            defaultsKey: "selectedLanguage"
        )

        #expect(controller.select(optionID: "zh-Hans"))
        #expect(String(localized: "General", bundle: controller.localizedBundle) == "通用")

        #expect(controller.select(optionID: "en"))
        #expect(String(localized: "General", bundle: controller.localizedBundle) == "General")
    }

    @MainActor
    @Test("System Default keeps the Mac's full locale while an explicit choice pins the language")
    func systemDefaultLocaleFollowsTheMac() throws {
        let suiteName = "AppLanguagePreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = AppLanguageController(
            defaults: defaults,
            bundle: .main,
            defaultsKey: "selectedLanguage"
        )

        // System Default must not collapse the environment locale onto a
        // region-less language locale; regional formatting follows the Mac.
        #expect(controller.locale == Locale.current)

        #expect(controller.select(optionID: "en"))
        #expect(controller.locale == Locale(identifier: "en"))

        #expect(controller.select(optionID: AppLanguageOption.systemID))
        #expect(controller.locale == Locale.current)
    }
}
