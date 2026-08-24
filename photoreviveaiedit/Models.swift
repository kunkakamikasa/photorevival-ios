import SwiftUI

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
    case enhanceVideo
    case photoToVideo
    case aiImage
    case fusion
    case enhancePhoto
    case textToVideo
    case imageToImage
    case textToImage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneTapRestore: "One-Tap Restore"
        case .enhanceVideo: "Enhance Video"
        case .photoToVideo: "Photo To Video"
        case .aiImage: "AI Image"
        case .fusion: "Fusion"
        case .enhancePhoto: "Enhance Photo"
        case .textToVideo: "Text To Video"
        case .imageToImage: "Image to Image"
        case .textToImage: "Text to Image"
        }
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
    let promptTemplate: String?
    let estimatedCredits: Int
    let modelType: String?
    let modelID: String?

    /// Image upload pages support one or two image inputs. CMS material
    /// requirements are mapped to `imageReferenceCount`; this keeps malformed
    /// or future configurations from creating a third layout.
    var imageUploadCount: Int {
        min(max(imageReferenceCount, 1), 2)
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
        promptTemplate: String? = nil,
        estimatedCredits: Int = 0,
        modelType: String? = nil,
        modelID: String? = nil
    ) {
        self.id = id
        self.title = title
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
        self.detailGroupTitle = detailGroupTitle
        self.showsPrompt = showsPrompt
        self.promptTemplate = promptTemplate
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
            promptTemplate: promptTemplate,
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
            promptTemplate: promptTemplate,
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
            promptTemplate: promptTemplate,
            estimatedCredits: estimatedCredits,
            modelType: modelType,
            modelID: modelID
        )
    }

    func withPreviewMedia(from previewItem: TemplateItem) -> TemplateItem {
        TemplateItem(
            id: id,
            title: title,
            imageName: previewItem.imageName,
            videoName: previewItem.videoName,
            coverImageURL: previewItem.coverImageURL,
            coverVideoURL: previewItem.coverVideoURL,
            comparisonCover: previewItem.comparisonCover,
            orientation: previewItem.orientation,
            badge: badge,
            generationKind: generationKind,
            imageReferenceCount: imageReferenceCount,
            detailGroupID: detailGroupID,
            detailGroupTitle: detailGroupTitle,
            showsPrompt: showsPrompt,
            promptTemplate: promptTemplate,
            estimatedCredits: estimatedCredits,
            modelType: modelType,
            modelID: modelID
        )
    }

}

struct TemplateDetailEntry: Identifiable, Hashable {
    let displayItem: TemplateItem
    let tryNowItem: TemplateItem?

    var id: String { displayItem.id }

    init(displayItem: TemplateItem, tryNowItem: TemplateItem?) {
        self.displayItem = displayItem
        self.tryNowItem = tryNowItem
    }

    init(item: TemplateItem) {
        self.init(displayItem: item, tryNowItem: item)
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
    let items: [TemplateItem]
    let generationKind: TemplateGenerationKind
    /// The CMS section ordering. Local catalog sections leave this unset and
    /// retain their declaration order when sections are merged for Home.
    let sortOrder: Int?

    init(
        _ title: String,
        id: String? = nil,
        badge: String? = nil,
        items: [TemplateItem],
        generationKind: TemplateGenerationKind = .video,
        sortOrder: Int? = nil
    ) {
        let resolvedID = id ?? title
        self.id = resolvedID
        self.title = title
        self.badge = badge
        self.generationKind = generationKind
        self.sortOrder = sortOrder
        self.items = items.map {
            $0.inGenerationGroup(
                generationKind,
                detailGroupID: resolvedID,
                detailGroupTitle: title
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
        if let configuredBadge = section.badge {
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
    static let textToVideoWhale = TemplateItem(
        id: "text-to-video-whale",
        title: "Text To Video",
        videoName: "text_to_video_whale_cover",
        orientation: .landscape
    )
    static let photoToVideo = TemplateItem(
        id: "photo-to-video-cover",
        title: "Photo To Video",
        videoName: "photo_to_video_cover",
        orientation: .landscape
    )
    static let fusion = TemplateItem(
        id: "fusion-cover",
        title: "Fusion",
        videoName: "fusion_cover",
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
    static let belovedBaby = TemplateItem(
        id: "dear-baby-beloved-baby",
        title: "Beloved Baby",
        videoName: "dear_baby_beloved_baby"
    )
    static let ourChildren = TemplateItem(
        id: "dear-baby-our-children",
        title: "Our Children",
        videoName: "dear_baby_our_children"
    )
    static let growUp = TemplateItem(
        id: "dear-baby-grow-up",
        title: "Grow up",
        videoName: "dear_baby_grow_up"
    )
    static let birthday = TemplateItem(
        id: "dear-baby-birthday",
        title: "Birthday",
        videoName: "dear_baby_birthday"
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
    static let enhanceVideo = TemplateItem(
        id: "enhance-video-cover",
        title: "Enhance Video",
        imageName: "Fashion",
        videoName: "enhance_comparison_cover",
        orientation: .landscape
    )
    static let enhancePhoto = TemplateItem(
        id: "enhance-photo-cover",
        title: "Enhance Photo",
        imageName: "EnhanceFeatureCard",
        videoName: "enhance_photo_comparison_cover",
        orientation: .landscape
    )
    static let gptImage = TemplateItem(
        id: "gpt-image-cover",
        title: "AI Image",
        imageName: "GPTImageMagicCover",
        videoName: "gpt_image_magic_cover",
        orientation: .landscape
    )

    static let homeHeroItems = [schoolWave, cinematic, fashionShow].map { $0.inDetailGroup("home-hero") }
    static let photoHeroItems = [cinematic, fashionShow, schoolWave].map { $0.inDetailGroup("photo-hero") }
    static let videoHeroItems = [schoolWave, cinematic, fashionShow].map { $0.inDetailGroup("video-hero") }
    static let localPhotoHeroEntries: [TemplateDetailEntry] = {
        let assetNames = ["AIPhotoCarousel3", "AIPhotoCarousel1", "AIPhotoCarousel2"].sorted {
            photoCarouselNumber(in: $0) < photoCarouselNumber(in: $1)
        }

        return zip(assetNames, photoHeroItems).map { assetName, template in
            TemplateDetailEntry(
                displayItem: template
                    .inGenerationGroup(.image)
                    .withImage(named: assetName),
                tryNowItem: template.inGenerationGroup(.image)
            )
        }
    }()
    static let photoToolItems = [memory, fashion, anime].map { $0.inDetailGroup("photo-tools") }

    private static func photoCarouselNumber(in assetName: String) -> Int {
        Int(String(assetName.reversed().prefix { $0.isNumber }.reversed())) ?? .max
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
        TemplateSection("Restore & Colorize", items: [memory, fashion, gentleman, cowboy], generationKind: .image)
    ]

    static let videoSections = [
        TemplateSection("Baby Adventure", items: [babyFly, motorcycle, skiing, cartoon], generationKind: .video),
        TemplateSection("Dear Baby", items: [belovedBaby, ourChildren, growUp, birthday], generationKind: .video),
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
