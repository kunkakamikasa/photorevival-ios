import SwiftUI

enum EnglishDisplayText {
    private static let titleTrimCharacters = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: "-–—·|/\\,\u{FF0C}\u{3001}()[]{}")
    )

    static func hasHanCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2FDF,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2EBEF,
                 0x2F800...0x2FA1F,
                 0x30000...0x323AF:
                true
            default:
                false
            }
        }
    }

    static func title(_ value: String?, fallback: String) -> String {
        guard let value else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        guard hasHanCharacters(trimmed) else { return trimmed }

        let filteredCharacters = trimmed.unicodeScalars.compactMap { scalar -> Character? in
            guard !isHan(scalar), !isCJKPunctuation(scalar) else { return nil }
            return Character(String(scalar))
        }
        let filtered = String(filteredCharacters)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: titleTrimCharacters)
        return filtered.isEmpty ? fallback : filtered
    }

    static func sectionTitle(
        _ value: String?,
        id: String,
        generationKind: TemplateGenerationKind
    ) -> String {
        if let value, hasHanCharacters(value) {
            switch id {
            case "cms-section-6561":
                return "Supermodel Runway"
            case "cms-section-6567":
                return "God-Tier Live Suspect"
            default:
                break
            }
        }
        return title(
            value,
            fallback: generationKind == .video ? "Featured Videos" : "Featured Photos"
        )
    }

    static func prompt(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !hasHanCharacters(trimmed) else { return nil }
        return value
    }

    /// Server and StoreKit messages can follow the device or provider locale.
    /// The app is English-only, so never surface a message containing Han
    /// characters. Keep the original error in logs and show a safe English
    /// fallback in the UI instead.
    static func userFacingMessage(_ value: String?, fallback: String) -> String {
        guard let value else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !hasHanCharacters(trimmed) else { return fallback }
        return trimmed
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        hasHanCharacters(String(scalar))
    }

    private static func isCJKPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F, 0xFF00...0xFFEF:
            true
        default:
            false
        }
    }
}

enum VideoPromptSubmission {
    /// The polished default is only a display layer. Submit a prompt override
    /// when the CMS permits editing and the user has actually changed the text.
    static func userOverride(
        displayedPrompt: String,
        defaultDisplayedPrompt: String,
        isEditable: Bool
    ) -> String? {
        guard isEditable else { return nil }
        let trimmedPrompt = displayedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDefault = defaultDisplayedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, trimmedPrompt != trimmedDefault else { return nil }
        return trimmedPrompt
    }
}

struct VideoGenerationOptionCapabilities: Equatable {
    let supportsSound: Bool
    let supportsMultiShot: Bool
    let durations: [String]
    let resolutions: [String]
    let aspectRatios: [String]

    static let seedance15 = VideoGenerationOptionCapabilities(
        supportsSound: true,
        supportsMultiShot: true,
        durations: ["5s", "8s", "10s"],
        resolutions: ["480p", "720p", "1080p"],
        aspectRatios: ["16:9", "1:1", "9:16", "4:3", "3:4"]
    )

    static let grokVideo = VideoGenerationOptionCapabilities(
        supportsSound: true,
        supportsMultiShot: false,
        durations: ["5s", "8s", "10s"],
        resolutions: ["480p", "720p", "1080p"],
        aspectRatios: ["16:9", "1:1", "9:16", "4:3", "3:4"]
    )

    /// Unknown future CMS models get a deliberately small, server-safe set.
    /// A new model must be explicitly mapped before richer controls appear.
    static let conservativeFallback = VideoGenerationOptionCapabilities(
        supportsSound: false,
        supportsMultiShot: false,
        durations: ["5s"],
        resolutions: ["480p"],
        aspectRatios: ["9:16"]
    )

    static func current(forModelID modelID: String?) -> VideoGenerationOptionCapabilities {
        let normalized = modelID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if normalized.contains("seedance-1-5") {
            return .seedance15
        }
        if normalized.contains("grok") && normalized.contains("video") {
            return .grokVideo
        }
        return .conservativeFallback
    }

    func normalizedDuration(_ value: String) -> String {
        durations.contains(value) ? value : durations[0]
    }

    func normalizedResolution(_ value: String) -> String {
        resolutions.contains(value) ? value : resolutions[0]
    }

    func normalizedAspectRatio(_ value: String) -> String {
        aspectRatios.contains(value) ? value : aspectRatios[0]
    }
}

struct ImageGenerationOptionCapabilities: Equatable {
    let resolutions: [String]
    let aspectRatios: [String]
    let outputCounts: [String]

    static let seedream45 = ImageGenerationOptionCapabilities(
        resolutions: ["2K"],
        aspectRatios: ["1:1", "4:3", "3:4", "16:9", "9:16", "3:2", "2:3", "21:9"],
        outputCounts: ["1"]
    )

    /// Models that have not been explicitly verified must not receive an
    /// aspect ratio. This keeps deprecated or future CMS models from inheriting
    /// Seedream-specific controls by accident.
    static let conservativeFallback = ImageGenerationOptionCapabilities(
        resolutions: [PhotoReviveImageGenerationOptions.providerDefaultResolution],
        aspectRatios: [],
        outputCounts: ["1"]
    )

    static func current(forModelID modelID: String?) -> ImageGenerationOptionCapabilities {
        let normalized = modelID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if normalized.contains("seedream-4-5") {
            return .seedream45
        }
        return .conservativeFallback
    }

    func normalizedResolution(_ value: String) -> String {
        resolutions.contains(value) ? value : resolutions[0]
    }

    func normalizedAspectRatio(_ value: String) -> String? {
        guard let defaultAspectRatio = aspectRatios.first else { return nil }
        return aspectRatios.contains(value) ? value : defaultAspectRatio
    }

    func normalizedOutputCount(_ value: String) -> String {
        outputCounts.contains(value) ? value : outputCounts[0]
    }
}

extension Error {
    func userFacingEnglishMessage(
        fallback: String = "Something went wrong. Please try again."
    ) -> String {
        EnglishDisplayText.userFacingMessage(localizedDescription, fallback: fallback)
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case photo
    case video
    case me

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .photo: "AI Photo"
        case .video: "AI Video"
        case .me: "Me"
        }
    }

    var pageTitle: String {
        switch self {
        case .home: ""
        case .photo: "AI Photo"
        case .video: "AI Video"
        case .me: "My Creations"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .photo: "photo.stack.fill"
        case .video: "play.rectangle.fill"
        case .me: "person.crop.circle"
        }
    }
}

enum FixedFeature: String, CaseIterable, Identifiable {
    case oneTapRestore
    case photoToVideo
    case aiImage
    case enhancePhoto
    case textToVideo
    case imageToImage
    case textToImage

    var id: String { rawValue }

    nonisolated init?(cmsKey: String) {
        switch cmsKey {
        case "restore": self = .oneTapRestore
        case "photo_to_video": self = .photoToVideo
        case "ai_image": self = .aiImage
        case "enhance_photo": self = .enhancePhoto
        case "text_to_video": self = .textToVideo
        case "image_to_image": self = .imageToImage
        case "text_to_image": self = .textToImage
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .oneTapRestore: "One-Tap Restore"
        case .photoToVideo: "Photo To Video"
        case .aiImage: "AI Image"
        case .enhancePhoto: "Enhance Photo"
        case .textToVideo: "Text To Video"
        case .imageToImage: "Image to Image"
        case .textToImage: "Text to Image"
        }
    }
}

struct AppCreditPricing: Hashable, Decodable {
    let oneTapRestoreCredits: Int
    let videoBaseCredits: Int
    let videoDefaultDurationSeconds: Int
    let videoExtraDurationCreditsPerSecond: Int
    let videoSoundCredits: Int
    let videoMultiShotCredits: Int
    let video720pExtraCreditsPerSecond: Int
    let video1080pExtraCreditsPerSecond: Int
    let otherVideoCredits: Int
    let enhancePhotoCredits: Int
    let imageToImageCredits: Int
    let textToImageCredits: Int
    let otherImageCredits: Int
    let defaultVideoResolution: String
    let defaultVideoSound: Bool
    let defaultVideoMultiShot: Bool

    static let defaultValue = AppCreditPricing()

    init(
        oneTapRestoreCredits: Int = 35,
        videoBaseCredits: Int = 40,
        videoDefaultDurationSeconds: Int = 5,
        videoExtraDurationCreditsPerSecond: Int = 8,
        videoSoundCredits: Int = 20,
        videoMultiShotCredits: Int = 20,
        video720pExtraCreditsPerSecond: Int = 4,
        video1080pExtraCreditsPerSecond: Int = 12,
        otherVideoCredits: Int = 60,
        enhancePhotoCredits: Int = 30,
        imageToImageCredits: Int = 30,
        textToImageCredits: Int = 30,
        otherImageCredits: Int = 30,
        defaultVideoResolution: String = "480p",
        defaultVideoSound: Bool = false,
        defaultVideoMultiShot: Bool = false
    ) {
        self.oneTapRestoreCredits = max(0, oneTapRestoreCredits)
        self.videoBaseCredits = max(0, videoBaseCredits)
        self.videoDefaultDurationSeconds = max(1, videoDefaultDurationSeconds)
        self.videoExtraDurationCreditsPerSecond = max(0, videoExtraDurationCreditsPerSecond)
        self.videoSoundCredits = max(0, videoSoundCredits)
        self.videoMultiShotCredits = max(0, videoMultiShotCredits)
        self.video720pExtraCreditsPerSecond = max(0, video720pExtraCreditsPerSecond)
        self.video1080pExtraCreditsPerSecond = max(0, video1080pExtraCreditsPerSecond)
        self.otherVideoCredits = max(0, otherVideoCredits)
        self.enhancePhotoCredits = max(0, enhancePhotoCredits)
        self.imageToImageCredits = max(0, imageToImageCredits)
        self.textToImageCredits = max(0, textToImageCredits)
        self.otherImageCredits = max(0, otherImageCredits)
        let normalizedVideoResolution = defaultVideoResolution
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.defaultVideoResolution = normalizedVideoResolution == "540p"
            ? "480p"
            : normalizedVideoResolution
        self.defaultVideoSound = defaultVideoSound
        self.defaultVideoMultiShot = defaultVideoMultiShot
    }

    func videoGenerationCredits(
        duration: Int,
        resolution: String,
        sound: Bool,
        multiShot: Bool
    ) -> Int {
        let duration = max(duration, 1)
        let extraDuration = max(duration - videoDefaultDurationSeconds, 0)
        let resolutionRate: Int
        switch resolution.lowercased() {
        case "1080p": resolutionRate = video1080pExtraCreditsPerSecond
        case "720p": resolutionRate = video720pExtraCreditsPerSecond
        default: resolutionRate = 0
        }
        return videoBaseCredits
            + extraDuration * videoExtraDurationCreditsPerSecond
            + duration * resolutionRate
            + (sound ? videoSoundCredits : 0)
            + (multiShot ? videoMultiShotCredits : 0)
    }

    private enum CodingKeys: String, CodingKey {
        case oneTapRestoreCredits = "one_tap_restore_credits"
        case videoBaseCredits = "video_base_credits"
        case videoDefaultDurationSeconds = "video_default_duration_seconds"
        case videoExtraDurationCreditsPerSecond = "video_extra_duration_credits_per_second"
        case videoSoundCredits = "video_sound_credits"
        case videoMultiShotCredits = "video_multi_shot_credits"
        case video720pExtraCreditsPerSecond = "video_720p_extra_credits_per_second"
        case video1080pExtraCreditsPerSecond = "video_1080p_extra_credits_per_second"
        case otherVideoCredits = "other_video_credits"
        case enhancePhotoCredits = "enhance_photo_credits"
        case imageToImageCredits = "image_to_image_credits"
        case textToImageCredits = "text_to_image_credits"
        case otherImageCredits = "other_image_credits"
        case defaultVideoResolution = "default_video_resolution"
        case defaultVideoSound = "default_video_sound"
        case defaultVideoMultiShot = "default_video_multi_shot"
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.defaultValue
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            oneTapRestoreCredits: try values.decodeIfPresent(Int.self, forKey: .oneTapRestoreCredits) ?? defaults.oneTapRestoreCredits,
            videoBaseCredits: try values.decodeIfPresent(Int.self, forKey: .videoBaseCredits) ?? defaults.videoBaseCredits,
            videoDefaultDurationSeconds: try values.decodeIfPresent(Int.self, forKey: .videoDefaultDurationSeconds) ?? defaults.videoDefaultDurationSeconds,
            videoExtraDurationCreditsPerSecond: try values.decodeIfPresent(Int.self, forKey: .videoExtraDurationCreditsPerSecond) ?? defaults.videoExtraDurationCreditsPerSecond,
            videoSoundCredits: try values.decodeIfPresent(Int.self, forKey: .videoSoundCredits) ?? defaults.videoSoundCredits,
            videoMultiShotCredits: try values.decodeIfPresent(Int.self, forKey: .videoMultiShotCredits) ?? defaults.videoMultiShotCredits,
            video720pExtraCreditsPerSecond: try values.decodeIfPresent(Int.self, forKey: .video720pExtraCreditsPerSecond) ?? defaults.video720pExtraCreditsPerSecond,
            video1080pExtraCreditsPerSecond: try values.decodeIfPresent(Int.self, forKey: .video1080pExtraCreditsPerSecond) ?? defaults.video1080pExtraCreditsPerSecond,
            otherVideoCredits: try values.decodeIfPresent(Int.self, forKey: .otherVideoCredits) ?? defaults.otherVideoCredits,
            enhancePhotoCredits: try values.decodeIfPresent(Int.self, forKey: .enhancePhotoCredits) ?? defaults.enhancePhotoCredits,
            imageToImageCredits: try values.decodeIfPresent(Int.self, forKey: .imageToImageCredits) ?? defaults.imageToImageCredits,
            textToImageCredits: try values.decodeIfPresent(Int.self, forKey: .textToImageCredits) ?? defaults.textToImageCredits,
            otherImageCredits: try values.decodeIfPresent(Int.self, forKey: .otherImageCredits) ?? defaults.otherImageCredits,
            defaultVideoResolution: try values.decodeIfPresent(String.self, forKey: .defaultVideoResolution) ?? defaults.defaultVideoResolution,
            defaultVideoSound: try values.decodeIfPresent(Bool.self, forKey: .defaultVideoSound) ?? defaults.defaultVideoSound,
            defaultVideoMultiShot: try values.decodeIfPresent(Bool.self, forKey: .defaultVideoMultiShot) ?? defaults.defaultVideoMultiShot
        )
    }
}

enum TemplateOrientation: String, Hashable {
    case landscape
    case portrait

    var aspectRatio: CGFloat {
        self == .landscape ? 4.0 / 3.0 : 2.0 / 3.0
    }
}

struct TemplateComparisonCover: Hashable {
    let beforeURL: URL
    let afterURL: URL
    let duration: TimeInterval

    init(beforeURL: URL, afterURL: URL, duration: TimeInterval = 2.4) {
        self.beforeURL = beforeURL
        self.afterURL = afterURL
        self.duration = max(0.8, duration)
    }
}

struct TemplateItem: Identifiable, Hashable {
    let id: String
    let title: String
    let imageName: String
    let videoName: String?
    let coverImageURL: URL?
    let coverVideoURL: URL?
    let comparisonCover: TemplateComparisonCover?
    let orientation: TemplateOrientation
    let badge: String?
    let generationKind: TemplateGenerationKind
    let imageReferenceCount: Int
    let detailGroupID: String?
    let detailGroupTitle: String?
    /// CMS template-level switch for the video upload page prompt card.
    let showsPrompt: Bool
    /// CMS template-level switch controlling whether the visible prompt can be changed.
    let promptIsEditable: Bool
    let promptTemplate: String?
    /// Optional CMS images aligned with Image1, Image2, Image3 upload slots.
    let uploadPlaceholderURLs: [URL?]
    let estimatedCredits: Int
    let modelType: String?
    let modelID: String?

    /// Multi-reference templates support up to three image inputs. Larger malformed
    /// CMS values are clamped so the upload screen stays usable on iPhone.
    var imageUploadCount: Int {
        min(max(imageReferenceCount, 1), 3)
    }

    /// Batch-published two-stage videos store the image-composition prompt and
    /// video-motion prompt in one compatibility field. The upload page should
    /// only use the second-stage motion prompt to build a display-safe summary.
    var displayedPromptTemplate: String? {
        guard generationKind == .video, let promptTemplate else { return nil }
        let visiblePrompt: String
        if let markerRange = promptTemplate.range(
            of: "VIDEO MOTION:",
            options: [.caseInsensitive]
        ) {
            let videoPrompt = promptTemplate[markerRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            visiblePrompt = videoPrompt.isEmpty ? promptTemplate : videoPrompt
        } else {
            visiblePrompt = promptTemplate
        }
        guard EnglishDisplayText.prompt(visiblePrompt) != nil else { return nil }
        return VideoPromptDisplayCatalog.prompt(for: id)
    }

    func uploadPlaceholderURL(at index: Int) -> URL? {
        guard uploadPlaceholderURLs.indices.contains(index) else { return nil }
        return uploadPlaceholderURLs[index]
    }

    init(
        id: String,
        title: String,
        imageName: String = "",
        videoName: String? = nil,
        coverImageURL: URL? = nil,
        coverVideoURL: URL? = nil,
        comparisonCover: TemplateComparisonCover? = nil,
        orientation: TemplateOrientation = .portrait,
        badge: String? = nil,
        generationKind: TemplateGenerationKind = .video,
        imageReferenceCount: Int = 1,
        detailGroupID: String? = nil,
        detailGroupTitle: String? = nil,
        showsPrompt: Bool = true,
        promptIsEditable: Bool = false,
        promptTemplate: String? = nil,
        uploadPlaceholderURLs: [URL?] = [],
        estimatedCredits: Int = 0,
        modelType: String? = nil,
        modelID: String? = nil
    ) {
        self.id = id
        let fallbackTitle = generationKind == .video ? "AI Video" : "AI Photo"
        self.title = EnglishDisplayText.title(title, fallback: fallbackTitle)
        self.imageName = imageName
        self.videoName = videoName
        self.coverImageURL = coverImageURL
        self.coverVideoURL = coverVideoURL
        self.comparisonCover = comparisonCover
        self.orientation = orientation
        self.badge = badge
        self.generationKind = generationKind
        self.imageReferenceCount = imageReferenceCount
        self.detailGroupID = detailGroupID
        self.detailGroupTitle = detailGroupTitle.map {
            EnglishDisplayText.title($0, fallback: fallbackTitle)
        }
        self.showsPrompt = showsPrompt
        self.promptIsEditable = promptIsEditable
        self.promptTemplate = promptTemplate
        self.uploadPlaceholderURLs = uploadPlaceholderURLs
        self.estimatedCredits = estimatedCredits
        self.modelType = modelType
        self.modelID = modelID
    }

    func inGenerationGroup(
        _ kind: TemplateGenerationKind,
        detailGroupID: String? = nil,
        detailGroupTitle: String? = nil
    ) -> TemplateItem {
        TemplateItem(
            id: id,
            title: title,
            imageName: imageName,
            videoName: videoName,
            coverImageURL: coverImageURL,
            coverVideoURL: coverVideoURL,
            comparisonCover: comparisonCover,
            orientation: orientation,
            badge: badge,
            generationKind: kind,
            imageReferenceCount: imageReferenceCount,
            detailGroupID: detailGroupID ?? self.detailGroupID,
            detailGroupTitle: detailGroupTitle ?? self.detailGroupTitle,
            showsPrompt: showsPrompt,
            promptIsEditable: promptIsEditable,
            promptTemplate: promptTemplate,
            uploadPlaceholderURLs: uploadPlaceholderURLs,
            estimatedCredits: estimatedCredits,
            modelType: modelType,
            modelID: modelID
        )
    }

    func inDetailGroup(_ groupID: String) -> TemplateItem {
        TemplateItem(
            id: id,
            title: title,
            imageName: imageName,
            videoName: videoName,
            coverImageURL: coverImageURL,
            coverVideoURL: coverVideoURL,
            comparisonCover: comparisonCover,
            orientation: orientation,
            badge: badge,
            generationKind: generationKind,
            imageReferenceCount: imageReferenceCount,
            detailGroupID: groupID,
            detailGroupTitle: detailGroupTitle,
            showsPrompt: showsPrompt,
            promptIsEditable: promptIsEditable,
            promptTemplate: promptTemplate,
            uploadPlaceholderURLs: uploadPlaceholderURLs,
            estimatedCredits: estimatedCredits,
            modelType: modelType,
            modelID: modelID
        )
    }

    func withImage(named imageName: String) -> TemplateItem {
        TemplateItem(
            id: id,
            title: title,
            imageName: imageName,
            videoName: videoName,
            coverImageURL: coverImageURL,
            coverVideoURL: coverVideoURL,
            comparisonCover: comparisonCover,
            orientation: orientation,
            badge: badge,
            generationKind: generationKind,
            imageReferenceCount: imageReferenceCount,
            detailGroupID: detailGroupID,
            detailGroupTitle: detailGroupTitle,
            showsPrompt: showsPrompt,
            promptIsEditable: promptIsEditable,
            promptTemplate: promptTemplate,
            uploadPlaceholderURLs: uploadPlaceholderURLs,
            estimatedCredits: estimatedCredits,
            modelType: modelType,
            modelID: modelID
        )
    }

    func withShowsPrompt(_ showsPrompt: Bool) -> TemplateItem {
        TemplateItem(
            id: id,
            title: title,
            imageName: imageName,
            videoName: videoName,
            coverImageURL: coverImageURL,
            coverVideoURL: coverVideoURL,
            comparisonCover: comparisonCover,
            orientation: orientation,
            badge: badge,
            generationKind: generationKind,
            imageReferenceCount: imageReferenceCount,
            detailGroupID: detailGroupID,
            detailGroupTitle: detailGroupTitle,
            showsPrompt: showsPrompt,
            promptIsEditable: promptIsEditable,
            promptTemplate: promptTemplate,
            uploadPlaceholderURLs: uploadPlaceholderURLs,
            estimatedCredits: estimatedCredits,
            modelType: modelType,
            modelID: modelID
        )
    }

    func withPromptControls(showsPrompt: Bool, promptIsEditable: Bool) -> TemplateItem {
        TemplateItem(
            id: id,
            title: title,
            imageName: imageName,
            videoName: videoName,
            coverImageURL: coverImageURL,
            coverVideoURL: coverVideoURL,
            comparisonCover: comparisonCover,
            orientation: orientation,
            badge: badge,
            generationKind: generationKind,
            imageReferenceCount: imageReferenceCount,
            detailGroupID: detailGroupID,
            detailGroupTitle: detailGroupTitle,
            showsPrompt: showsPrompt,
            promptIsEditable: promptIsEditable,
            promptTemplate: promptTemplate,
            uploadPlaceholderURLs: uploadPlaceholderURLs,
            estimatedCredits: estimatedCredits,
            modelType: modelType,
            modelID: modelID
        )
    }

}

struct TemplateDetailEntry: Identifiable, Hashable {
    let displayItem: TemplateItem
    let tryNowItem: TemplateItem?
    let fixedFeatureTarget: FixedFeature?

    var id: String { displayItem.id }

    init(
        displayItem: TemplateItem,
        tryNowItem: TemplateItem?,
        fixedFeatureTarget: FixedFeature? = nil
    ) {
        self.displayItem = displayItem
        self.tryNowItem = tryNowItem
        self.fixedFeatureTarget = fixedFeatureTarget
    }

    init(item: TemplateItem) {
        self.init(displayItem: item, tryNowItem: item)
    }
}

struct HomeQuickAction: Identifiable, Hashable {
    let feature: FixedFeature
    let title: String
    let item: TemplateItem
    let generationTargets: [FeatureGenerationTarget]

    var id: String { feature.id }
    var generationTarget: FeatureGenerationTarget? { generationTargets.first }

    init(
        feature: FixedFeature,
        title: String? = nil,
        item: TemplateItem,
        generationTarget: FeatureGenerationTarget? = nil,
        generationTargets: [FeatureGenerationTarget] = []
    ) {
        self.feature = feature
        self.title = EnglishDisplayText.title(title, fallback: feature.title)
        self.item = item
        self.generationTargets = generationTargets.isEmpty
            ? generationTarget.map { [$0] } ?? []
            : generationTargets
    }

    func generationTarget(endpoint: String) -> FeatureGenerationTarget? {
        generationTargets.first { $0.endpoint == endpoint }
    }
}

struct FeatureGenerationTarget: Hashable {
    let itemID: String
    let endpoint: String
    let modelType: String
    let modelID: String
    let estimatedCredits: Int
    let promptTemplate: String?
}

enum FixedFeatureGenerationTargetResolver {
    static func target(
        for feature: FixedFeature,
        endpoint: String,
        in quickActions: [HomeQuickAction]
    ) -> FeatureGenerationTarget? {
        if let directTarget = quickActions
            .first(where: { $0.feature == feature })?
            .generationTarget(endpoint: endpoint) {
            return directTarget
        }

        // The CMS publishes both AI Image modes under the combined
        // `ai_image.generation_targets` entry. The dedicated AI Photo tools
        // are UI aliases, so resolve them from that combined entry when a
        // legacy standalone fixed-feature item is not present.
        switch feature {
        case .imageToImage, .textToImage:
            return quickActions
                .first(where: { $0.feature == .aiImage })?
                .generationTarget(endpoint: endpoint)
        default:
            return nil
        }
    }
}

enum CouponPlanKind: String, CaseIterable, Identifiable, Hashable {
    case weekly
    case annual

    var id: String { rawValue }
}

struct CMSCouponPlan: Hashable {
    let productID: String
}

struct CMSCouponOffer: Identifiable, Hashable {
    let id: String
    let placement: String
    let coverImageURL: URL
    let weeklyPlan: CMSCouponPlan
    let annualPlan: CMSCouponPlan

    func plan(for kind: CouponPlanKind) -> CMSCouponPlan {
        kind == .weekly ? weeklyPlan : annualPlan
    }
}

private struct HomeSubscriptionCouponOfferKey: EnvironmentKey {
    static let defaultValue: CMSCouponOffer? = nil
}

extension EnvironmentValues {
    var homeSubscriptionCouponOffer: CMSCouponOffer? {
        get { self[HomeSubscriptionCouponOfferKey.self] }
        set { self[HomeSubscriptionCouponOfferKey.self] = newValue }
    }
}

struct CMSCreditPurchasePromotion: Identifiable, Hashable {
    let id: String
    let placement: String
    let coverImageURL: URL

    init(id: String, placement: String = "hero", coverImageURL: URL) {
        self.id = id
        self.placement = placement
        self.coverImageURL = coverImageURL
    }
}

enum CMSHomeHeroPromotion: Identifiable, Hashable {
    case subscriptionCoupon(CMSCouponOffer)
    case creditPurchase(CMSCreditPurchasePromotion)

    var id: String {
        switch self {
        case .subscriptionCoupon(let offer): "subscription-coupon-\(offer.id)"
        case .creditPurchase(let promotion): "credit-purchase-\(promotion.id)"
        }
    }

    var coverImageURL: URL {
        switch self {
        case .subscriptionCoupon(let offer): offer.coverImageURL
        case .creditPurchase(let promotion): promotion.coverImageURL
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .subscriptionCoupon: "Open special gift"
        case .creditPurchase: "Open credit store"
        }
    }

    static func visible(
        isSubscribed: Bool,
        coupon: CMSCouponOffer?,
        creditPurchase: CMSCreditPurchasePromotion?
    ) -> CMSHomeHeroPromotion? {
        if isSubscribed {
            return creditPurchase.map(Self.creditPurchase)
        }
        return coupon.map(Self.subscriptionCoupon)
    }
}

enum TemplateGenerationKind: String, Hashable {
    case image
    case video
}

struct TemplateSection: Identifiable {
    let id: String
    let title: String
    let badge: String?
    let showsPrompt: Bool?
    let promptIsEditable: Bool?
    let items: [TemplateItem]
    let generationKind: TemplateGenerationKind
    /// The CMS section ordering. Local catalog sections leave this unset and
    /// retain their declaration order when sections are merged for Home.
    let sortOrder: Int?

    init(
        _ title: String,
        id: String? = nil,
        badge: String? = nil,
        showsPrompt: Bool? = nil,
        promptIsEditable: Bool? = nil,
        items: [TemplateItem],
        generationKind: TemplateGenerationKind = .video,
        sortOrder: Int? = nil
    ) {
        let resolvedID = id ?? title
        let resolvedTitle = EnglishDisplayText.sectionTitle(
            title,
            id: resolvedID,
            generationKind: generationKind
        )
        self.id = resolvedID
        self.title = resolvedTitle
        self.badge = badge
        self.showsPrompt = showsPrompt
        self.promptIsEditable = promptIsEditable
        self.generationKind = generationKind
        self.sortOrder = sortOrder
        self.items = items.map { item in
            let configuredItem: TemplateItem
            if showsPrompt != nil || promptIsEditable != nil {
                configuredItem = item.withPromptControls(
                    showsPrompt: showsPrompt ?? item.showsPrompt,
                    promptIsEditable: promptIsEditable ?? item.promptIsEditable
                )
            } else {
                configuredItem = item
            }
            return configuredItem.inGenerationGroup(
                generationKind,
                detailGroupID: resolvedID,
                detailGroupTitle: resolvedTitle
            )
        }
    }

    /// Home contains both CMS menus. Sort configured sections by their shared
    /// section order, with video preceding image when both menus use the same
    /// order value (as the CMS currently does at order 5).
    static func mergedForHome(
        videoSections: [TemplateSection],
        imageSections: [TemplateSection]
    ) -> [TemplateSection] {
        let tagged = videoSections.enumerated().map { (section: $0.element, menuRank: 0, sourceIndex: $0.offset) }
            + imageSections.enumerated().map { (section: $0.element, menuRank: 1, sourceIndex: $0.offset) }

        return tagged.sorted { lhs, rhs in
            if let lhsOrder = lhs.section.sortOrder, let rhsOrder = rhs.section.sortOrder,
               lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            if lhs.section.sortOrder != nil, rhs.section.sortOrder == nil {
                return true
            }
            if lhs.section.sortOrder == nil, rhs.section.sortOrder != nil {
                return false
            }
            if lhs.menuRank != rhs.menuRank {
                return lhs.menuRank < rhs.menuRank
            }
            return lhs.sourceIndex < rhs.sourceIndex
        }
        .map(\.section)
    }
}

enum TemplateBadgePolicy {
    static func badge(for item: TemplateItem, at zeroBasedPosition: Int, on page: AppTab) -> String? {
        if let configuredBadge = item.badge {
            return TemplateBadgeValue.normalized(configuredBadge)
        }

        return switch (page, zeroBasedPosition) {
        case (.home, 0): "HOT"
        case (.home, 1): "NEW"
        case (.photo, 0): "HOT"
        default: nil
        }
    }

}

enum TemplateSectionBadgePolicy {
    static func badge(for section: TemplateSection, at zeroBasedPosition: Int, on page: AppTab) -> String? {
        if let configuredBadge = section.badge?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            switch configuredBadge {
            case "AUTO", "": return defaultBadge(at: zeroBasedPosition, on: page)
            case "HOT": return "HOT"
            case "NEW": return "NEW"
            case "NONE", "OFF": return nil
            default: return nil
            }
        }

        return defaultBadge(at: zeroBasedPosition, on: page)
    }

    private static func defaultBadge(at zeroBasedPosition: Int, on page: AppTab) -> String? {
        guard page != .me else { return nil }
        return switch zeroBasedPosition {
        case 0: "HOT"
        case 1: "NEW"
        default: nil
        }
    }

}

enum TemplateBadgeValue {
    static func normalized(_ badge: String?) -> String? {
        guard let badge else { return nil }
        return switch badge.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "HOT": "HOT"
        case "NEW": "NEW"
        case "", "NONE", "OFF": nil
        default: nil
        }
    }
}

enum TemplateCatalog {
    static let schoolWave = TemplateItem(
        id: "school-wave",
        title: "School Days",
        imageName: "SchoolWaveLandscape",
        videoName: "school_wave",
        orientation: .landscape
    )
    static let memory = TemplateItem(
        id: "memory",
        title: "Memory",
        imageName: "MemoryPortrait",
        videoName: "restore_comparison_cover",
        showsPrompt: false
    )
    static let babyFly = TemplateItem(
        id: "baby-fly",
        title: "Baby Fly",
        imageName: "BabyFly",
        videoName: "baby_fly"
    )
    static let motorcycle = TemplateItem(
        id: "motorcycle-boy",
        title: "Motorcycle Boy",
        imageName: "Motorcycle",
        videoName: "motorcycle"
    )
    static let skiing = TemplateItem(
        id: "baby-skiing",
        title: "Baby Skiing",
        imageName: "Skiing",
        videoName: "skiing"
    )
    static let fashion = TemplateItem(
        id: "fashion-dresses",
        title: "Fashion Dresses",
        imageName: "Fashion",
        videoName: "fashion",
        showsPrompt: false
    )
    static let cowboy = TemplateItem(
        id: "cowboy-style",
        title: "Cowboy Style",
        imageName: "Cowboy",
        videoName: "motorcycle",
        imageReferenceCount: 2,
        showsPrompt: false
    )
    static let gentleman = TemplateItem(
        id: "gentleman",
        title: "Gentleman",
        imageName: "Gentleman",
        videoName: "memory_portrait",
        showsPrompt: false
    )
    static let mangaRide = TemplateItem(
        id: "manga-ride",
        title: "Manga Rider",
        imageName: "MangaRide",
        videoName: "manga_ride"
    )
    static let cartoon = TemplateItem(
        id: "cartoon-portrait",
        title: "Playful Cartoon",
        imageName: "CartoonPortrait",
        videoName: "cartoon_portrait"
    )
    static let anime = TemplateItem(
        id: "anime-portrait",
        title: "Anime Story",
        imageName: "AnimePortrait",
        videoName: "anime_portrait"
    )
    static let cinematic = TemplateItem(
        id: "cinematic-memory",
        title: "Cinematic Memory",
        imageName: "MemoryPortrait",
        videoName: "memory_portrait",
        orientation: .landscape
    )
    static let fashionShow = TemplateItem(
        id: "fashion-show",
        title: "Fashion Show",
        imageName: "Fashion",
        videoName: "fashion",
        orientation: .landscape
    )
    static let homeHeroItems = [schoolWave, cinematic, fashionShow].map { $0.inDetailGroup("home-hero") }
    static let photoHeroItems = [cinematic, fashionShow, schoolWave].map { $0.inDetailGroup("photo-hero") }
    static let videoHeroItems = [schoolWave, cinematic, fashionShow].map { $0.inDetailGroup("video-hero") }
    static let photoToolItems = [memory, fashion, anime].map { $0.inDetailGroup("photo-tools") }

    static let homeQuickActions: [HomeQuickAction] = [
        .oneTapRestore,
        .photoToVideo,
        .aiImage,
        .enhancePhoto,
        .textToVideo
    ].map { feature in
        HomeQuickAction(
            feature: feature,
            item: TemplateItem(
                id: "local-fixed-\(feature.rawValue)",
                title: feature.title,
                orientation: .landscape
            )
        )
    }

    static let homeSections = [
        TemplateSection("Baby Adventure", items: [babyFly, motorcycle, skiing, cartoon], generationKind: .video),
        TemplateSection("Revive Old Photos", items: [memory, gentleman, fashion, cowboy], generationKind: .video),
        // Temporary local classification until the backend returns a generation type.
        TemplateSection("Stylized", items: [mangaRide, cartoon, anime, babyFly], generationKind: .image)
    ]

    static let photoSections = [
        TemplateSection("New Outfit", items: [fashion, cowboy, gentleman, anime], generationKind: .image),
        TemplateSection("Stylized", items: [mangaRide, cartoon, anime, babyFly], generationKind: .image),
        TemplateSection("One-Tap Restore", items: [memory, fashion, gentleman, cowboy], generationKind: .image)
    ]

    static let videoSections = [
        TemplateSection("Baby Adventure", items: [babyFly, motorcycle, skiing, cartoon], generationKind: .video),
        TemplateSection("Revive Old Photos", items: [memory, gentleman, fashion, cowboy], generationKind: .video),
        TemplateSection("Stylized", items: [mangaRide, cartoon, anime, babyFly], generationKind: .video)
    ]

    static func sections(for tab: AppTab) -> [TemplateSection] {
        switch tab {
        case .home: homeSections
        case .photo: photoSections
        case .video: videoSections
        case .me: []
        }
    }

    static func detailItems(for item: TemplateItem) -> [TemplateItem] {
        if let groupID = item.detailGroupID {
            let sections = homeSections + photoSections + videoSections
            if let section = sections.first(where: {
                $0.id == groupID &&
                    $0.generationKind == item.generationKind &&
                    $0.items.contains(where: { $0.id == item.id })
            }) {
                return section.items
            }

            let heroGroups = [homeHeroItems, photoHeroItems, videoHeroItems]
            if let heroItems = heroGroups.first(where: { $0.contains(where: { $0.id == item.id && $0.detailGroupID == groupID }) }) {
                return heroItems
            }

            if groupID == "photo-tools" {
                return photoToolItems
            }
        }

        let allItems = (homeSections + photoSections + videoSections).flatMap(\.items)
        var seenIDs = Set<String>()
        let uniqueItems = allItems.filter { seenIDs.insert($0.id).inserted }
        return uniqueItems.isEmpty ? [item] : uniqueItems
    }
}

enum AppPalette {
    static let backgroundTop = Color(red: 1.00, green: 0.96, blue: 0.84)
    static let backgroundBottom = Color(red: 0.91, green: 0.75, blue: 0.51)
    static let surfaceCenter = Color(red: 0.99, green: 0.91, blue: 0.74)
    static let surfaceEdge = Color(red: 0.72, green: 0.48, blue: 0.25)
    static let accent = Color(red: 0.93, green: 0.25, blue: 0.19)
    static let orange = Color(red: 1.00, green: 0.55, blue: 0.02)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.07)
    static let brownInk = Color(red: 0.58, green: 0.31, blue: 0.10)
}
