import Foundation
import SwiftUI

struct AppLanguageSelection: Hashable {
    enum Language: String, CaseIterable, Hashable {
        case english = "en"
        case arabic = "ar"
        case filipino = "fil"
        case hebrew = "he"
        case hindi = "hi"
        case indonesian = "id"
        case japanese = "ja"
        case malay = "ms"
        case turkish = "tr"
        case urdu = "ur"
        case vietnamese = "vi"

        var isRightToLeft: Bool {
            switch self {
            case .arabic, .hebrew, .urdu:
                true
            default:
                false
            }
        }
    }

    let language: Language
    let localeIdentifier: String

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    var layoutDirection: LayoutDirection {
        language.isRightToLeft ? .rightToLeft : .leftToRight
    }

    /// Uses the phone's primary language only. If that language is unsupported,
    /// English wins even when another supported language appears later in the
    /// user's language list.
    static func resolve(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguageSelection {
        guard let preferredIdentifier = preferredLanguages.first else {
            return englishFallback
        }

        let normalizedIdentifier = preferredIdentifier
            .replacingOccurrences(of: "_", with: "-")
        guard let rawLanguageCode = normalizedIdentifier
            .split(separator: "-", omittingEmptySubsequences: true)
            .first?
            .lowercased(),
              let language = language(for: rawLanguageCode) else {
            return englishFallback
        }

        let canonicalIdentifier = canonicalLocaleIdentifier(
            normalizedIdentifier,
            rawLanguageCode: rawLanguageCode,
            language: language
        )
        return AppLanguageSelection(
            language: language,
            localeIdentifier: canonicalIdentifier
        )
    }

    private static let englishFallback = AppLanguageSelection(
        language: .english,
        localeIdentifier: Language.english.rawValue
    )

    private static func language(for code: String) -> Language? {
        switch code {
        case "en": .english
        case "ar": .arabic
        case "fil", "tl": .filipino
        case "he", "iw": .hebrew
        case "hi": .hindi
        case "id", "in": .indonesian
        case "ja": .japanese
        case "ms": .malay
        case "tr": .turkish
        case "ur": .urdu
        case "vi": .vietnamese
        default: nil
        }
    }

    private static func canonicalLocaleIdentifier(
        _ identifier: String,
        rawLanguageCode: String,
        language: Language
    ) -> String {
        guard rawLanguageCode != language.rawValue else { return identifier }
        let suffix = identifier.dropFirst(rawLanguageCode.count)
        return language.rawValue + suffix
    }
}

enum AppLocalization {
    static func string(
        _ source: String,
        selection: AppLanguageSelection = .resolve()
    ) -> String {
        guard selection.language != .english,
              let path = Bundle.main.path(
                forResource: selection.language.rawValue,
                ofType: "lproj"
              ),
              let localizedBundle = Bundle(path: path) else {
            return source
        }

        return localizedBundle.localizedString(
            forKey: source,
            value: source,
            table: "Localizable"
        )
    }

    /// Dynamic labels use explicit language bundles so an unsupported primary
    /// phone language cannot fall through to a supported secondary language.
    /// These known APIs keep those keys visible to Xcode's string extractor.
    private static let extractionKeys = [
        String(localized: "Home"),
        String(localized: "AI Photo"),
        String(localized: "AI Video"),
        String(localized: "Me"),
        String(localized: "My Creations"),
        String(localized: "Video"),
        String(localized: "Photo"),
        String(localized: "One-Tap Restore"),
        String(localized: "AI Image"),
        String(localized: "Enhance Photo"),
        String(localized: "Text To Video"),
        String(localized: "Image to Image"),
        String(localized: "Text to Image"),
        String(localized: "Uploaded"),
        String(localized: "Created"),
        String(localized: "All"),
        String(localized: "Spent"),
        String(localized: "Earned"),
        String(localized: "ORIGINAL"),
        String(localized: "FREEFORM"),
    ]
}
