import Combine
import Foundation

@MainActor
final class FeatureConfigStore: ObservableObject {
    @Published private(set) var videoSections: [TemplateSection] = []
    @Published private(set) var imageSections: [TemplateSection] = []
    @Published private(set) var homeCarouselEntries: [TemplateDetailEntry] = []
    @Published private(set) var photoCarouselEntries: [TemplateDetailEntry] = []
    @Published private(set) var videoCarouselEntries: [TemplateDetailEntry] = []
    @Published private(set) var isLoading = true

    private var hasStartedLoading = false
    private var loadGeneration = 0

    /// Home is a cross-menu catalog. The CMS controls the section order, so
    /// keep the video and image tabs separate while exposing one ordered list
    /// for the Home feed.
    var homeSections: [TemplateSection] {
        TemplateSection.mergedForHome(
            videoSections: videoSections,
            imageSections: imageSections
        )
    }

    func heroEntries(for tab: AppTab) -> [TemplateDetailEntry] {
        let configured: [TemplateDetailEntry]
        let fallbackItems: [TemplateItem]
        switch tab {
        case .home:
            configured = homeCarouselEntries
            fallbackItems = Array(homeSections.flatMap(\.items).prefix(3))
        case .photo:
            return TemplateCatalog.localPhotoHeroEntries
        case .video:
            configured = videoCarouselEntries
            fallbackItems = Array(videoSections.flatMap(\.items).prefix(3))
        case .me:
            return []
        }
        return configured.isEmpty ? fallbackItems.map(TemplateDetailEntry.init(item:)) : configured
    }

    func detailItems(for item: TemplateItem) -> [TemplateItem] {
        guard let groupID = item.detailGroupID,
              let section = (videoSections + imageSections).first(where: {
                  $0.id == groupID && $0.generationKind == item.generationKind
              }) else {
            return [item]
        }
        return section.items
    }

    func load() async {
        await load(force: false)
    }

    /// Re-fetch the audience-scoped catalog after Adjust resolves attribution.
    /// Adjust callbacks can arrive after the initial screen has started loading,
    /// so the first request may have used the conservative `noad` audience.
    func reloadAfterAttributionChange() async {
        guard !ProcessInfo.processInfo.arguments.contains("-useLocalFeatureCatalog") else { return }
        await load(force: true)
    }

    private func load(force: Bool) async {
        guard force || !hasStartedLoading else { return }
        hasStartedLoading = true
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        if ProcessInfo.processInfo.arguments.contains("-useLocalFeatureCatalog") {
            videoSections = TemplateCatalog.videoSections
            imageSections = TemplateCatalog.photoSections
            homeCarouselEntries = TemplateCatalog.homeHeroItems.map(TemplateDetailEntry.init(item:))
            photoCarouselEntries = TemplateCatalog.photoHeroItems.map(TemplateDetailEntry.init(item:))
            videoCarouselEntries = TemplateCatalog.videoHeroItems.map(TemplateDetailEntry.init(item:))
            return
        }

        await AdjustService.shared.waitForInitialAttribution()
        let referrer = AdjustService.shared.referrer

        async let fetchedVideoSections = fetchSections(
            menu: "video",
            generationKind: .video,
            referrer: referrer
        )
        async let fetchedImageSections = fetchSections(
            menu: "image",
            generationKind: .image,
            referrer: referrer
        )
        async let fetchedCarousels = fetchCarousels(referrer: referrer)

        do {
            let remoteSections = try await fetchedVideoSections
            guard generation == loadGeneration else { return }
            videoSections = Self.addingLocalDearBabyItems(to: remoteSections)
        } catch {
            // An empty catalog is intentional: do not restore placeholder covers on failure.
        }
        do {
            let remoteSections = try await fetchedImageSections
            guard generation == loadGeneration else { return }
            imageSections = remoteSections
        } catch {
            // Keep the fixed photo tools usable when the remote catalog is unavailable.
        }

        do {
            let carousels = try await fetchedCarousels
            guard generation == loadGeneration else { return }
            homeCarouselEntries = carousels[.home] ?? []
            photoCarouselEntries = carousels[.photo] ?? []
            videoCarouselEntries = carousels[.video] ?? []
        } catch {
            // Section covers remain as a fallback if carousel configuration is unavailable.
        }
    }

    private func fetchSections(
        menu: String,
        generationKind: TemplateGenerationKind,
        referrer: String
    ) async throws -> [TemplateSection] {
        var components = URLComponents(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("functions/v1/get-feature-configs"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "app_id", value: PhotoReviveAPIConfig.appID),
            URLQueryItem(name: "menu", value: menu),
            URLQueryItem(name: "page_type", value: "default"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "referrer", value: referrer)
        ]
        guard let url = components?.url else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            return []
        }

        let payload = try JSONDecoder().decode(FeatureConfigResponse.self, from: data)
        return payload.sections
            .enumerated()
            .sorted { lhs, rhs in
                configuredOrder(lhs.element.sortOrder, rhs.element.sortOrder)
                    || (lhs.element.sortOrder == rhs.element.sortOrder && lhs.offset < rhs.offset)
            }
            .compactMap { $0.element.templateSection(generationKind: generationKind) }
    }

    private func fetchCarousels(referrer: String) async throws -> [RemoteCarouselPage: [TemplateDetailEntry]] {
        var components = URLComponents(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("functions/v1/get-app-carousels"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "app_id", value: PhotoReviveAPIConfig.appID),
            URLQueryItem(name: "referrer", value: referrer)
        ]
        guard let url = components?.url else { return [:] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            return [:]
        }

        let payload = try JSONDecoder().decode(RemoteCarouselResponse.self, from: data)
        return Dictionary(grouping: payload.items.compactMap(\.detailEntry), by: { $0.page })
            .mapValues { $0.map { $0.entry } }
    }

    /// Keep the three bundled Dear Baby previews available while the CMS
    /// rollout is in progress. The CMS-owned item remains authoritative for
    /// any matching title or id; only missing local items are appended.
    private static func addingLocalDearBabyItems(to sections: [TemplateSection]) -> [TemplateSection] {
        let localItems = [
            TemplateCatalog.ourChildren,
            TemplateCatalog.growUp,
            TemplateCatalog.birthday
        ]

        guard let index = sections.firstIndex(where: {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Dear Baby") == .orderedSame
        }) else {
            return sections
        }

        let existingKeys = Set(sections[index].items.flatMap { item in
            [item.id.lowercased(), item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        })
        let missingItems = localItems.filter {
            !existingKeys.contains($0.id.lowercased())
                && !existingKeys.contains($0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        guard !missingItems.isEmpty else { return sections }

        var result = sections
        let existing = result[index]
        result[index] = TemplateSection(
            existing.title,
            id: existing.id,
            badge: existing.badge,
            items: existing.items + missingItems,
            generationKind: existing.generationKind,
            sortOrder: existing.sortOrder
        )
        return result
    }
}

private struct FeatureConfigResponse: Decodable {
    let sections: [RemoteFeatureSection]
}

private func configuredOrder(_ lhs: Int?, _ rhs: Int?) -> Bool {
    switch (lhs, rhs) {
    case let (lhs?, rhs?) where lhs != rhs:
        return lhs < rhs
    case (.some, .none):
        return true
    default:
        return false
    }
}

private enum RemoteCarouselPage: String, Decodable, Hashable {
    case home
    case photo
    case video
}

private enum RemoteCarouselCoverType: String, Decodable {
    case image
    case video
    case comparison
}

private struct RemoteCarouselResponse: Decodable {
    let items: [RemoteCarouselItem]
}

private struct RemoteCarouselTarget: Decodable {
    let id: Int
    let title: String?
    let menu: String
}

private struct RemoteCarouselItem: Decodable {
    let id: String
    let page: RemoteCarouselPage
    let title: String
    let coverType: RemoteCarouselCoverType
    let coverImageURL: String?
    let coverVideoURL: String?
    let coverBeforeImageURL: String?
    let coverAfterImageURL: String?
    let beforeImageURL: String?
    let afterImageURL: String?
    let coverAnimationDuration: Double?
    let comparisonCover: RemoteComparisonCover?
    let targetTemplate: RemoteCarouselTarget?
    let targetFilter: RemoteFeatureItem?

    enum CodingKeys: String, CodingKey {
        case id, page, title
        case coverType = "cover_type"
        case coverImageURL = "cover_image_url"
        case coverVideoURL = "cover_video_url"
        case coverBeforeImageURL = "cover_before_image_url"
        case coverAfterImageURL = "cover_after_image_url"
        case beforeImageURL = "before_image_url"
        case afterImageURL = "after_image_url"
        case coverAnimationDuration = "cover_animation_duration"
        case comparisonCover = "comparison_cover"
        case targetTemplate = "target_template"
        case targetFilter = "target_filter"
    }

    var detailEntry: (page: RemoteCarouselPage, entry: TemplateDetailEntry)? {
        let imageURL = coverImageURL.flatMap(URL.init(string:))
        let videoURL = coverType == .video ? coverVideoURL.flatMap(URL.init(string:)) : nil
        let comparison = comparisonCoverValue
        guard coverType == .video
            ? videoURL != nil
            : (imageURL != nil || comparison != nil) else { return nil }

        let generationKind: TemplateGenerationKind = targetTemplate?.menu == "image" ? .image : .video
        let tryNowItem: TemplateItem?
        if let targetTemplate, let targetFilter {
            let groupID = "cms-section-\(targetTemplate.id)"
            tryNowItem = targetFilter.templateItem(
                groupID: groupID,
                groupTitle: targetTemplate.title,
                generationKind: generationKind
            )
        } else {
            tryNowItem = nil
        }

        let displayItem = TemplateItem(
            id: "cms-carousel-\(id)",
            title: title,
            coverImageURL: imageURL,
            coverVideoURL: videoURL,
            comparisonCover: comparison,
            orientation: .landscape,
            generationKind: generationKind,
            detailGroupID: "cms-carousel-\(page.rawValue)",
            detailGroupTitle: targetTemplate?.title
        )
        return (page, TemplateDetailEntry(displayItem: displayItem, tryNowItem: tryNowItem))
    }

    private var comparisonCoverValue: TemplateComparisonCover? {
        let before = (comparisonCover?.beforeImageURL
            ?? coverBeforeImageURL
            ?? beforeImageURL).flatMap(URL.init(string:))
        let after = (comparisonCover?.afterImageURL
            ?? coverAfterImageURL
            ?? afterImageURL).flatMap(URL.init(string:))
        guard let before, let after else { return nil }

        return TemplateComparisonCover(
            beforeURL: before,
            afterURL: after,
            duration: comparisonCover?.duration ?? coverAnimationDuration ?? 2.4
        )
    }
}

private struct RemoteFeatureSection: Decodable {
    let id: Int
    let title: String?
    let badge: String?
    let sortOrder: Int?
    let items: [RemoteFeatureItem]

    enum CodingKeys: String, CodingKey {
        case id, title, badge, items
        case sortOrder = "sort_order"
    }

    func templateSection(generationKind: TemplateGenerationKind) -> TemplateSection? {
        guard let title, !title.isEmpty else { return nil }
        let groupID = "cms-section-\(id)"
        let mappedItems = items
            .enumerated()
            .sorted { lhs, rhs in
                configuredOrder(lhs.element.sortOrder, rhs.element.sortOrder)
                    || (lhs.element.sortOrder == rhs.element.sortOrder && lhs.offset < rhs.offset)
            }
            .compactMap { $0.element.templateItem(groupID: groupID, generationKind: generationKind) }
        guard !mappedItems.isEmpty else { return nil }
        return TemplateSection(
            title,
            id: groupID,
            badge: badge,
            items: mappedItems,
            generationKind: generationKind,
            sortOrder: sortOrder
        )
    }
}

private struct RemoteFeatureItem: Decodable {
    let id: String
    let title: String
    let badge: String?
    let sortOrder: Int?
    let promptTemplate: String?
    let estimatedCredits: Int
    let modelType: String?
    let modelID: String?
    let coverImage: String?
    let coverVideo: String?
    let coverVideoThumbnail: String?
    let requiresPreview: Bool?
    let previewStyle: String?
    let previewConfig: RemotePreviewConfig?
    /// Template-level switch for whether the video upload page shows prompt text.
    let showPrompt: Bool?
    let coverType: String?
    let coverBeforeImageURL: String?
    let coverAfterImageURL: String?
    let beforeImageURL: String?
    let afterImageURL: String?
    let coverAnimationDuration: Double?
    let comparisonCover: RemoteComparisonCover?
    let materialRequirements: [RemoteMaterialRequirement]

    enum CodingKeys: String, CodingKey {
        case id, title, badge
        case sortOrder = "sort_order"
        case promptTemplate = "prompt_template"
        case estimatedCredits = "estimated_credits"
        case modelType = "model_type"
        case modelID = "model_id"
        case coverImage = "cover_image_url"
        case coverVideo = "cover_video"
        case coverVideoThumbnail = "cover_video_thumbnail"
        case requiresPreview = "requires_preview"
        case previewStyle = "preview_style"
        case previewConfig = "preview_config"
        case showPrompt = "show_prompt"
        case coverType = "cover_type"
        case coverBeforeImageURL = "cover_before_image_url"
        case coverAfterImageURL = "cover_after_image_url"
        case beforeImageURL = "before_image_url"
        case afterImageURL = "after_image_url"
        case coverAnimationDuration = "cover_animation_duration"
        case comparisonCover = "comparison_cover"
        case materialRequirements = "material_requirements"
    }

    func templateItem(
        groupID: String,
        groupTitle: String? = nil,
        generationKind: TemplateGenerationKind
    ) -> TemplateItem? {
        // Image filters are static previews even if an accidental video URL is present in CMS.
        let coverVideoURL = generationKind == .video ? coverVideo.flatMap(URL.init(string:)) : nil
        let coverImageURL = (coverImage ?? coverVideoThumbnail).flatMap(URL.init(string:))
        let comparison = comparisonCoverValue

        guard coverImageURL != nil || comparison != nil else { return nil }
        if generationKind == .video && coverVideoURL == nil { return nil }

        let referenceCount = materialRequirements.reduce(0) { count, requirement in
            switch requirement.type {
            case "single_image": count + 1
            case "multiple_images": count + (requirement.imageCount ?? 1)
            default: count
            }
        }

        // Both image uploads and prompt-enabled video uploads have only a
        // one-image or two-image variant, determined by material requirements.
        let imageUploadCount = min(max(referenceCount, 1), 2)
        let resolvedShowPrompt = showPrompt ?? !(promptTemplate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        return TemplateItem(
            id: id,
            title: title,
            coverImageURL: coverImageURL,
            coverVideoURL: coverVideoURL,
            comparisonCover: comparison,
            badge: badge,
            generationKind: generationKind,
            imageReferenceCount: imageUploadCount,
            detailGroupID: groupID,
            detailGroupTitle: groupTitle,
            showsPrompt: resolvedShowPrompt,
            promptTemplate: promptTemplate,
            estimatedCredits: estimatedCredits,
            modelType: modelType,
            modelID: modelID
        )
    }

    private var comparisonCoverValue: TemplateComparisonCover? {
        let usesCMSImageComparison = requiresPreview == true && previewStyle == "image_comparison"
        let before = ((usesCMSImageComparison ? previewConfig?.beforeImageURL : nil)
            ?? comparisonCover?.beforeImageURL
            ?? coverBeforeImageURL
            ?? beforeImageURL).flatMap(URL.init(string:))
        let after = ((usesCMSImageComparison ? previewConfig?.afterImageURL : nil)
            ?? comparisonCover?.afterImageURL
            ?? coverAfterImageURL
            ?? afterImageURL).flatMap(URL.init(string:))
        guard let before, let after else { return nil }

        return TemplateComparisonCover(
            beforeURL: before,
            afterURL: after,
            duration: comparisonCover?.duration ?? coverAnimationDuration ?? 2.4
        )
    }
}

private struct RemotePreviewConfig: Decodable {
    let beforeImageURL: String?
    let afterImageURL: String?

    enum CodingKeys: String, CodingKey {
        case beforeImageURL = "before_image_url"
        case afterImageURL = "after_image_url"
    }
}

private struct RemoteComparisonCover: Decodable {
    let beforeImageURL: String?
    let afterImageURL: String?
    let duration: Double?

    enum CodingKeys: String, CodingKey {
        case beforeImageURL = "before_image_url"
        case afterImageURL = "after_image_url"
        case duration
    }
}

private struct RemoteMaterialRequirement: Decodable {
    let type: String
    let imageCount: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case imageCount = "image_count"
    }
}
