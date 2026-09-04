import SwiftUI
import Testing
@testable import photoreviveaiedit

struct AppLanguageTests {
    @Test("App bundle contains every supported localization")
    func bundleContainsSupportedLocalizations() {
        let expected = Set(["en", "ar", "fil", "he", "hi", "id", "ja", "ms", "tr", "ur", "vi"])

        #expect(Set(Bundle.main.localizations).isSuperset(of: expected))
    }

    @Test("String catalog resolves target-language text and format placeholders")
    func stringCatalogResolvesTranslations() {
        #expect(
            AppLocalization.string(
                "Home",
                selection: .resolve(preferredLanguages: ["ja-JP"])
            ) == "ホーム"
        )
        #expect(
            AppLocalization.string(
                "Home",
                selection: .resolve(preferredLanguages: ["ar-SA"])
            ) == "الرئيسية"
        )
        #expect(
            AppLocalization.string(
                "%lld credits",
                selection: .resolve(preferredLanguages: ["vi-VN"])
            ) == "%lld tín dụng"
        )
        #expect(
            AppLocalization.string(
                "Home",
                selection: .resolve(preferredLanguages: ["zh-Hans-CN", "ja-JP"])
            ) == "Home"
        )
    }

    @Test("Welcome screen copy is translated for every supported non-English language")
    func welcomeScreenCopyIsFullyLocalized() {
        let sourceStrings = [
            "AI-POWERED",
            "Bring Your Favorite Moments to Life",
            "RESTORE • ENHANCE • ANIMATE",
        ]
        let targetLanguages = [
            "ar-SA", "fil-PH", "he-IL", "hi-IN", "id-ID",
            "ja-JP", "ms-MY", "tr-TR", "ur-PK", "vi-VN",
        ]

        for language in targetLanguages {
            let selection = AppLanguageSelection.resolve(
                preferredLanguages: [language]
            )

            for source in sourceStrings {
                let localized = AppLocalization.string(source, selection: selection)
                #expect(!localized.isEmpty)
                #expect(localized != source)
            }
        }
    }

    @Test("Supported phone languages select the matching app language")
    func supportedLanguagesFollowPhone() {
        let expected: [(String, AppLanguageSelection.Language)] = [
            ("ar-EG", .arabic),
            ("ar-SA", .arabic),
            ("fil-PH", .filipino),
            ("ms-MY", .malay),
            ("ja-JP", .japanese),
            ("tr-TR", .turkish),
            ("ur-PK", .urdu),
            ("he-IL", .hebrew),
            ("hi-IN", .hindi),
            ("id-ID", .indonesian),
            ("en-GB", .english),
            ("vi-VN", .vietnamese),
        ]

        for (identifier, language) in expected {
            let selection = AppLanguageSelection.resolve(
                preferredLanguages: [identifier]
            )
            #expect(selection.language == language)
            #expect(selection.localeIdentifier == identifier)
        }
    }

    @Test("Unsupported primary phone language falls back to English")
    func unsupportedLanguageFallsBackToEnglish() {
        let selection = AppLanguageSelection.resolve(
            preferredLanguages: ["zh-Hans-CN", "ja-JP"]
        )

        #expect(selection.language == .english)
        #expect(selection.localeIdentifier == "en")
        #expect(selection.layoutDirection == .leftToRight)
    }

    @Test("Empty phone language list falls back to English")
    func emptyLanguageListFallsBackToEnglish() {
        let selection = AppLanguageSelection.resolve(preferredLanguages: [])

        #expect(selection.language == .english)
        #expect(selection.localeIdentifier == "en")
    }

    @Test("Legacy Apple language codes map to current localizations")
    func legacyLanguageAliasesAreSupported() {
        #expect(
            AppLanguageSelection.resolve(preferredLanguages: ["tl-PH"])
                .localeIdentifier == "fil-PH"
        )
        #expect(
            AppLanguageSelection.resolve(preferredLanguages: ["iw-IL"])
                .localeIdentifier == "he-IL"
        )
        #expect(
            AppLanguageSelection.resolve(preferredLanguages: ["in-ID"])
                .localeIdentifier == "id-ID"
        )
    }

    @Test("Arabic, Hebrew, and Urdu use right-to-left layout")
    func rightToLeftLanguages() {
        for identifier in ["ar-EG", "ar-SA", "he-IL", "ur-PK"] {
            #expect(
                AppLanguageSelection.resolve(preferredLanguages: [identifier])
                    .layoutDirection == .rightToLeft
            )
        }

        for identifier in ["en-US", "fil-PH", "hi-IN", "ja-JP"] {
            #expect(
                AppLanguageSelection.resolve(preferredLanguages: [identifier])
                    .layoutDirection == .leftToRight
            )
        }
    }
}
