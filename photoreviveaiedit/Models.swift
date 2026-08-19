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

struct TemplateItem: Identifiable, Hashable {
    let id: String
    let title: String
    let imageName: String
    let videoName: String?
    let coverImageURL: URL?
    let coverVideoURL: URL?
    let orientation: TemplateOrientation
    let badge: String?
    let generationKind: TemplateGenerationKind
    let imageReferenceCount: Int
    let detailGroupID: String?
    let promptTemplate: String?
    let estimatedCredits: Int
    let modelType: String?
    let modelID: String?

    init(
        id: String,
        title: String,
        imageName: String = "",
        videoName: String? = nil,
        coverImageURL: URL? = nil,
        coverVideoURL: URL? = nil,
        orientation: TemplateOrientation = .portrait,
        badge: String? = nil,
        generationKind: TemplateGenerationKind = .video,
        imageReferenceCount: Int = 1,
        detailGroupID: String? = nil,
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
        self.orientation = orientation
        self.badge = badge
        self.generationKind = generationKind
        self.imageReferenceCount = imageReferenceCount
        self.detailGroupID = detailGroupID
        self.promptTemplate = promptTemplate
        self.estimatedCredits = estimatedCredits
        self.modelType = modelType
        self.modelID = modelID
    }

    func inGenerationGroup(
        _ kind: TemplateGenerationKind,
        detailGroupID: String? = nil
    ) -> TemplateItem {
        TemplateItem(
            id: id,
            title: title,
            imageName: imageName,
            videoName: videoName,
            coverImageURL: coverImageURL,
            coverVideoURL: coverVideoURL,
            orientation: orientation,
            badge: badge,
            generationKind: kind,
            imageReferenceCount: imageReferenceCount,
            detailGroupID: detailGroupID ?? self.detailGroupID,
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
            orientation: orientation,
            badge: badge,
            generationKind: generationKind,
            imageReferenceCount: imageReferenceCount,
            detailGroupID: groupID,
            promptTemplate: promptTemplate,
            estimatedCredits: estimatedCredits,
            modelType: modelType,
            modelID: modelID
        )
    }
}

enum TemplateGenerationKind: String, Hashable {
    case image
    case video
}

struct TemplateSection: Identifiable {
    let id: String
    let title: String
    let items: [TemplateItem]
    let generationKind: TemplateGenerationKind

    init(
        _ title: String,
        id: String? = nil,
        items: [TemplateItem],
        generationKind: TemplateGenerationKind = .video
    ) {
        self.id = id ?? title
        self.title = title
        self.generationKind = generationKind
        self.items = items.map { $0.inGenerationGroup(generationKind, detailGroupID: title) }
    }
}

enum TemplateCatalog {
    static let schoolWave = TemplateItem(
        id: "school-wave",
        title: "School Days",
        imageName: "SchoolWaveLandscape",
        videoName: "school_wave",
        orientation: .landscape,
        badge: "NEW"
    )
    static let memory = TemplateItem(
        id: "memory",
        title: "Memory",
        imageName: "MemoryPortrait",
        videoName: "memory_portrait"
    )
    static let babyFly = TemplateItem(
        id: "baby-fly",
        title: "Baby Fly",
        imageName: "BabyFly",
        videoName: "baby_fly",
        badge: "NEW"
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
        badge: "HOT"
    )
    static let cowboy = TemplateItem(
        id: "cowboy-style",
        title: "Cowboy Style",
        imageName: "Cowboy",
        videoName: "motorcycle",
        imageReferenceCount: 2
    )
    static let gentleman = TemplateItem(
        id: "gentleman",
        title: "Gentleman",
        imageName: "Gentleman",
        videoName: "memory_portrait"
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
