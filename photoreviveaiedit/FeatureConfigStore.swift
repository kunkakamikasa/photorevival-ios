import Combine
import Foundation

@MainActor
final class FeatureConfigStore: ObservableObject {
    @Published private(set) var videoSections: [TemplateSection] = []
    @Published private(set) var imageSections: [TemplateSection] = []
    @Published private(set) var homeCarouselEntries: [TemplateDetailEntry] = []
    @Published private(set) var photoCarouselEntries: [TemplateDetailEntry] = []
    @Published private(set) var videoCarouselEntries: [TemplateDetailEntry] = []
    @Published private(set) var homeQuickActions: [HomeQuickAction] = []
    @Published private(set) var creditPricing = AppCreditPricing.defaultValue
    @Published private(set) var homeHeroOffer: CMSCouponOffer?
    @Published private(set) var homeBottomOffer: CMSCouponOffer?
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

    var videoModeActions: [HomeQuickAction] {
        // `get-app-fixed-features` only returns enabled Home entries and keeps
        // their CMS order. The AI Video header mirrors the first four visible
        // Home entries, so a disabled slot is replaced by the next enabled one.
        Array(homeQuickActions.prefix(4))
    }

    func heroEntries(for tab: AppTab) -> [TemplateDetailEntry] {
        let configured: [TemplateDetailEntry]
        let fallbackItems: [TemplateItem]
        switch tab {
        case .home:
            configured = homeCarouselEntries
            fallbackItems = Array(homeSections.flatMap(\.items).prefix(3))
        case .photo:
            return photoCarouselEntries
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

    /// Returns one continuous, CMS-ordered detail feed. The selected filter is
    /// first, followed by the rest of its section and every following section.
    /// Earlier filters wrap to the end so a detail screen never stops merely
    /// because the user reached the boundary of the section they opened.
    func browsingItems(for item: TemplateItem, on tab: AppTab) -> [TemplateItem] {
        let sections: [TemplateSection]
        switch tab {
        case .home:
            sections = homeSections
        case .photo:
            sections = imageSections
        case .video:
            sections = videoSections
        case .me:
            sections = []
        }

        let allItems = sections.flatMap(\.items)
        let selectedIndex = allItems.firstIndex {
            $0.id == item.id
                && $0.generationKind == item.generationKind
                && $0.detailGroupID == item.detailGroupID
        } ?? allItems.firstIndex {
            $0.id == item.id && $0.generationKind == item.generationKind
        }

        let orderedItems: [TemplateItem]
        if let selectedIndex {
            orderedItems = [item]
                + Array(allItems.dropFirst(selectedIndex + 1))
                + Array(allItems.prefix(selectedIndex))
        } else {
            orderedItems = [item] + allItems
        }

        // A filter can be reused in more than one CMS section. SwiftUI paging
        // requires stable unique ids, so show its first occurrence only.
        var seenIDs = Set<String>()
        return orderedItems.filter { seenIDs.insert($0.id).inserted }
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
            homeQuickActions = TemplateCatalog.homeQuickActions
            creditPricing = .defaultValue
            homeHeroOffer = nil
            homeBottomOffer = nil
            return
        }

        // Do not hold the catalog behind Adjust's four-second attribution
        // window. The initial no-ad catalog can load under the startup video;
        // the existing attribution notification refreshes it if targeting
        // resolves to a different audience later.
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
        async let fetchedQuickActions = fetchQuickActions()

        do {
            let remoteSections = try await fetchedVideoSections
            guard generation == loadGeneration else { return }
            videoSections = Self.addingLocalDearBabyItems(to: remoteSections)
            prefetchInitialCovers()
        } catch {
            // An empty catalog is intentional: do not restore placeholder covers on failure.
        }
        do {
            let remoteSections = try await fetchedImageSections
            guard generation == loadGeneration else { return }
            imageSections = remoteSections
            prefetchInitialCovers()
        } catch {
            // Keep the fixed photo tools usable when the remote catalog is unavailable.
        }

        do {
            let carousels = try await fetchedCarousels
            guard generation == loadGeneration else { return }
            homeCarouselEntries = carousels.entries[.home] ?? []
            photoCarouselEntries = carousels.entries[.photo] ?? []
            videoCarouselEntries = carousels.entries[.video] ?? []
            homeHeroOffer = carousels.homeHeroOffer
            homeBottomOffer = carousels.homeBottomOffer
            prefetchInitialCovers()
        } catch {
            // Section covers remain as a fallback if carousel configuration is unavailable.
        }

        do {
            let fixedFeatures = try await fetchedQuickActions
            guard generation == loadGeneration else { return }
            // The endpoint only returns enabled features. Accept partial and empty
            // responses so CMS switches can hide one shortcut or the entire row.
            homeQuickActions = fixedFeatures.quickActions
            creditPricing = fixedFeatures.creditPricing
            prefetchInitialCovers()
        } catch {
            // Do not restore bundled covers: Home keeps the CMS-only result.
        }
    }

    /// Warm the media the user is most likely to see next. Prefetching is
    /// deliberately narrow and sequential inside the repository, leaving
    /// transfer slots available for covers that have actually appeared.
    private func prefetchInitialCovers() {
        var items = [TemplateItem]()
        items.append(contentsOf: homeCarouselEntries.prefix(3).map(\.displayItem))
        items.append(contentsOf: homeQuickActions.prefix(4).map(\.item))
        items.append(contentsOf: homeSections.prefix(3).flatMap { $0.items.prefix(3) })
        items.append(contentsOf: imageSections.prefix(3).compactMap { $0.items.first })
        items.append(contentsOf: videoSections.prefix(2).compactMap { $0.items.first })

        var urls = items.flatMap { item -> [URL] in
            if let comparison = item.comparisonCover {
                return [comparison.beforeURL, comparison.afterURL]
            }
            return item.coverImageURL.map { [$0] } ?? []
        }
        if let homeHeroOffer { urls.insert(homeHeroOffer.coverImageURL, at: 0) }
        if let homeBottomOffer { urls.append(homeBottomOffer.coverImageURL) }
        TemplateMediaPreloader.prefetchImages(urls)
    }

    private func fetchQuickActions() async throws -> FixedFeatureLoadResult {
        var components = URLComponents(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("functions/v1/get-app-fixed-features"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "app_id", value: PhotoReviveAPIConfig.appID)]
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(RemoteFixedFeatureResponse.self, from: data)
        return FixedFeatureLoadResult(
            quickActions: payload.items.compactMap(\.quickAction),
            creditPricing: payload.creditPricing ?? .defaultValue
        )
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

    private func fetchCarousels(referrer: String) async throws -> CarouselLoadResult {
        var components = URLComponents(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent("functions/v1/get-app-carousels"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "app_id", value: PhotoReviveAPIConfig.appID),
            URLQueryItem(name: "referrer", value: referrer)
        ]
        guard let url = components?.url else { return CarouselLoadResult() }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            return CarouselLoadResult()
        }

        let payload = try JSONDecoder().decode(RemoteCarouselResponse.self, from: data)
        let detailEntries: [(page: RemoteCarouselPage, entry: TemplateDetailEntry)] = payload.items.compactMap { item in
            guard item.normalizedPlacement == "hero" else { return nil }
            // AI Photo only accepts an image cover, but its destination is CMS-driven.
            return item.page == .photo ? item.photoImageEntry : item.detailEntry
        }
        let mappedEntries = Dictionary(grouping: detailEntries, by: { $0.page })
        .mapValues { $0.map { $0.entry } }

        let offers = payload.items.compactMap(\.couponOffer)
        return CarouselLoadResult(
            entries: mappedEntries,
            homeHeroOffer: offers.first { $0.placement == "hero" },
            homeBottomOffer: offers.first { $0.placement == "bottom_banner" }
        )
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
            showsPrompt: existing.showsPrompt,
            promptIsEditable: existing.promptIsEditable,
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

private struct CarouselLoadResult {
    var entries: [RemoteCarouselPage: [TemplateDetailEntry]] = [:]
    var homeHeroOffer: CMSCouponOffer?
    var homeBottomOffer: CMSCouponOffer?
}

private struct RemoteFixedFeatureResponse: Decodable {
    let items: [RemoteFixedFeatureItem]
    let creditPricing: AppCreditPricing?

    enum CodingKeys: String, CodingKey {
        case items
        case creditPricing = "credit_pricing"
    }
}

private struct FixedFeatureLoadResult {
    let quickActions: [HomeQuickAction]
    let creditPricing: AppCreditPricing
}

private enum RemoteFixedFeatureCoverType: String, Decodable {
    case image
    case video
}

private struct RemoteFixedFeatureItem: Decodable {
    let featureKey: String
    let title: String
    let coverType: RemoteFixedFeatureCoverType
    let coverImageURL: String?
    let coverVideoURL: String?

    enum CodingKeys: String, CodingKey {
        case featureKey = "feature_key"
        case title
        case coverType = "cover_type"
        case coverImageURL = "cover_image_url"
        case coverVideoURL = "cover_video_url"
    }

    var quickAction: HomeQuickAction? {
        guard let feature = FixedFeature(cmsKey: featureKey) else { return nil }
        let imageURL = coverImageURL.flatMap(URL.init(string:))
        let videoURL = coverVideoURL.flatMap(URL.init(string:))
        guard coverType == .video ? videoURL != nil : imageURL != nil else { return nil }

        let item = TemplateItem(
            id: "cms-fixed-feature-\(featureKey)",
            title: title,
            coverImageURL: imageURL,
            coverVideoURL: videoURL,
            orientation: .landscape,
            generationKind: coverType == .video ? .video : .image
        )
        return HomeQuickAction(feature: feature, title: title, item: item)
    }
}

private struct RemoteCarouselTarget: Decodable {
    let id: Int
    let title: String?
    let menu: String
    let showPrompt: Bool?
    let promptEditable: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, menu
        case showPrompt = "show_prompt"
        case promptEditable = "prompt_editable"
    }
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
    let targetKind: String?
    let targetFixedFeatureKey: String?
    let contentKind: String?
    let placement: String?
    let coupon: RemoteCouponConfiguration?

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
        case targetKind = "target_kind"
        case targetFixedFeatureKey = "target_fixed_feature_key"
        case contentKind = "content_kind"
        case placement
        case coupon
    }

    var normalizedPlacement: String {
        placement?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "hero"
    }

    var normalizedTargetKind: String {
        if let targetKind = targetKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !targetKind.isEmpty {
            return targetKind
        }
        if targetTemplate != nil, targetFilter != nil { return "try_now" }
        // Backward compatibility with the old hard-coded AI Photo action.
        if page == .photo { return "fixed_feature" }
        return "none"
    }

    var fixedFeatureTarget: FixedFeature? {
        guard normalizedTargetKind == "fixed_feature" else { return nil }
        let key = targetFixedFeatureKey ?? (page == .photo ? "ai_image" : nil)
        return key.flatMap(FixedFeature.init(cmsKey:))
    }

    var couponOffer: CMSCouponOffer? {
        guard page == .home,
              contentKind?.lowercased() == "coupon",
              let coupon,
              let coverImageURL = coverImageURL.flatMap(URL.init(string:)),
              let weekly = coupon.weekly.plan,
              let annual = coupon.annual.plan else {
            return nil
        }

        return CMSCouponOffer(
            id: id,
            placement: normalizedPlacement,
            coverImageURL: coverImageURL,
            weeklyPlan: weekly,
            annualPlan: annual
        )
    }

    var detailEntry: (page: RemoteCarouselPage, entry: TemplateDetailEntry)? {
        guard contentKind?.lowercased() != "coupon" else { return nil }
        let imageURL = coverImageURL.flatMap(URL.init(string:))
        let videoURL = coverType == .video ? coverVideoURL.flatMap(URL.init(string:)) : nil
        let comparison = comparisonCoverValue
        guard coverType == .video
            ? videoURL != nil
            : (imageURL != nil || comparison != nil) else { return nil }

        let generationKind: TemplateGenerationKind
        if let targetTemplate {
            generationKind = targetTemplate.menu == "image" ? .image : .video
        } else {
            generationKind = coverType == .video ? .video : .image
        }
        let tryNowItem: TemplateItem?
        if normalizedTargetKind == "try_now", let targetTemplate, let targetFilter {
            let groupID = "cms-section-\(targetTemplate.id)"
            tryNowItem = targetFilter.templateItem(
                groupID: groupID,
                groupTitle: targetTemplate.title,
                generationKind: generationKind,
                showsPrompt: targetTemplate.showPrompt ?? false,
                promptIsEditable: targetTemplate.promptEditable ?? false
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
        return (
            page,
            TemplateDetailEntry(
                displayItem: displayItem,
                tryNowItem: tryNowItem,
                fixedFeatureTarget: fixedFeatureTarget
            )
        )
    }

    var photoImageEntry: (page: RemoteCarouselPage, entry: TemplateDetailEntry)? {
        guard page == .photo,
              contentKind?.lowercased() != "coupon",
              let imageURL = coverImageURL.flatMap(URL.init(string:)) else {
            return nil
        }

        let tryNowItem: TemplateItem?
        if normalizedTargetKind == "try_now", let targetTemplate, let targetFilter {
            let groupID = "cms-section-\(targetTemplate.id)"
            tryNowItem = targetFilter.templateItem(
                groupID: groupID,
                groupTitle: targetTemplate.title,
                generationKind: .image,
                showsPrompt: targetTemplate.showPrompt ?? false,
                promptIsEditable: targetTemplate.promptEditable ?? false
            )
        } else {
            tryNowItem = nil
        }

        let displayItem = TemplateItem(
            id: "cms-photo-carousel-\(id)",
            title: title,
            coverImageURL: imageURL,
            orientation: .landscape,
            generationKind: .image
        )
        return (
            page,
            TemplateDetailEntry(
                displayItem: displayItem,
                tryNowItem: tryNowItem,
                fixedFeatureTarget: fixedFeatureTarget
            )
        )
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

private struct RemoteCouponConfiguration: Decodable {
    let weekly: RemoteCouponPlan
    let annual: RemoteCouponPlan
}

private struct RemoteCouponPlan: Decodable {
    let productID: String

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
    }

    var plan: CMSCouponPlan? {
        let productID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !productID.isEmpty else { return nil }
        return CMSCouponPlan(productID: productID)
    }
}

private struct RemoteFeatureSection: Decodable {
    let id: Int
    let title: String?
    let badge: String?
    let showPrompt: Bool?
    let promptEditable: Bool?
    let sortOrder: Int?
    let items: [RemoteFeatureItem]

    enum CodingKeys: String, CodingKey {
        case id, title, badge, items
        case showPrompt = "show_prompt"
        case promptEditable = "prompt_editable"
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
            .compactMap {
                $0.element.templateItem(
                    groupID: groupID,
                    generationKind: generationKind,
                    showsPrompt: showPrompt ?? false,
                    promptIsEditable: promptEditable ?? false
                )
            }
        guard !mappedItems.isEmpty else { return nil }
        return TemplateSection(
            title,
            id: groupID,
            badge: badge,
            showsPrompt: showPrompt ?? false,
            promptIsEditable: promptEditable ?? false,
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
        generationKind: TemplateGenerationKind,
        showsPrompt: Bool,
        promptIsEditable: Bool
    ) -> TemplateItem? {
        // Image filters are static previews even if an accidental video URL is present in CMS.
        let coverVideoURL = generationKind == .video ? coverVideo.flatMap(URL.init(string:)) : nil
        let coverImageURL = (coverImage ?? coverVideoThumbnail).flatMap(URL.init(string:))
        let comparison = comparisonCoverValue

        guard coverImageURL != nil || comparison != nil else { return nil }
        if generationKind == .video && coverVideoURL == nil { return nil }

        var uploadPlaceholderURLs: [URL?] = []
        for requirement in materialRequirements where uploadPlaceholderURLs.count < 3 {
            let slotCount: Int
            switch requirement.type {
            case "single_image": slotCount = 1
            case "multiple_images": slotCount = max(requirement.imageCount ?? 1, 1)
            default: continue
            }
            let configuredCovers = requirement.coverRequired == true
                ? (requirement.coverImages ?? [])
                : []
            for slotIndex in 0..<min(slotCount, 3 - uploadPlaceholderURLs.count) {
                let placeholderURL = configuredCovers.indices.contains(slotIndex)
                    ? URL(string: configuredCovers[slotIndex])
                    : nil
                uploadPlaceholderURLs.append(placeholderURL)
            }
        }

        // Upload count is controlled by image material requirements and is
        // independent from prompt visibility/editability.
        let imageUploadCount = min(max(uploadPlaceholderURLs.count, 1), 3)
        if uploadPlaceholderURLs.isEmpty {
            uploadPlaceholderURLs = [nil]
        }
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
            showsPrompt: showsPrompt,
            promptIsEditable: promptIsEditable,
            promptTemplate: promptTemplate,
            uploadPlaceholderURLs: Array(uploadPlaceholderURLs.prefix(imageUploadCount)),
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
    let coverRequired: Bool?
    let coverImages: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case imageCount = "image_count"
        case coverRequired = "cover_required"
        case coverImages = "cover_images"
    }
}
