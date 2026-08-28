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
    @Published private(set) var homeCreditPurchasePromotion: CMSCreditPurchasePromotion?
    @Published private(set) var homeBottomOffer: CMSCouponOffer?
    @Published private(set) var homeBottomCreditPurchasePromotion: CMSCreditPurchasePromotion?
    @Published private(set) var isLoading = true
    @Published private(set) var hasResolvedInitialCarouselLoad = false

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
        let waitsForRemoteCarousel: Bool
        switch tab {
        case .home:
            configured = homeCarouselEntries
            fallbackItems = Array(homeSections.flatMap(\.items).prefix(3))
            waitsForRemoteCarousel = !hasResolvedInitialCarouselLoad
        case .photo:
            return photoCarouselEntries
        case .video:
            configured = videoCarouselEntries
            fallbackItems = Array(videoSections.flatMap(\.items).prefix(3))
            waitsForRemoteCarousel = false
        case .me:
            return []
        }
        return Self.displayedHeroEntries(
            configured: configured,
            fallbackItems: fallbackItems,
            waitsForRemoteCarousel: waitsForRemoteCarousel
        )
    }

    static func displayedHeroEntries(
        configured: [TemplateDetailEntry],
        fallbackItems: [TemplateItem],
        waitsForRemoteCarousel: Bool
    ) -> [TemplateDetailEntry] {
        guard !waitsForRemoteCarousel else { return [] }
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

    /// Result suggestions are CMS-owned. Prefer other filters in the current
    /// section, then fill the remaining slots from other CMS image sections.
    func imageRecommendations(for item: TemplateItem?, limit: Int = 4) -> [TemplateItem] {
        guard limit > 0 else { return [] }

        let allImageItems = imageSections.flatMap(\.items)
        let sameSectionItems: [TemplateItem]
        if let item,
           let groupID = item.detailGroupID,
           let section = imageSections.first(where: { $0.id == groupID }) {
            sameSectionItems = section.items.filter { $0.id != item.id }
        } else {
            sameSectionItems = []
        }

        var seen = Set<String>()
        if let item { seen.insert(item.id) }
        let preferred = sameSectionItems.filter { seen.insert($0.id).inserted }
        let remaining = allImageItems
            .filter { seen.insert($0.id).inserted }
            .shuffled()
        return Array((preferred + remaining).prefix(limit))
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
            homeCreditPurchasePromotion = nil
            homeBottomOffer = nil
            homeBottomCreditPurchasePromotion = nil
            hasResolvedInitialCarouselLoad = true
            return
        }

        // Do not hold the catalog behind Adjust's four-second attribution
        // window. The initial no-ad catalog can load under the startup video;
        // the existing attribution notification refreshes it if targeting
        // resolves to a different audience later.
        let referrer = AdjustService.shared.referrer

        let storedSnapshot = await CatalogSnapshotStore.load(
            appID: PhotoReviveAPIConfig.appID,
            referrer: referrer
        )
        let matchingSnapshot = storedSnapshot.flatMap {
            $0.appID == PhotoReviveAPIConfig.appID && $0.referrer == referrer ? $0 : nil
        }
        if !force, let matchingSnapshot, restore(matchingSnapshot) {
            // The old catalog is immediately usable while all four endpoints
            // refresh independently in the background.
            isLoading = false
            TemplateMediaMetrics.shared.markCatalogAvailable(source: "snapshot")
        }

        var currentSnapshot = matchingSnapshot ?? CatalogSnapshot(
            appID: PhotoReviveAPIConfig.appID,
            referrer: referrer
        )
        let requests = CatalogComponent.allCases.compactMap { component -> (CatalogComponent, URL)? in
            guard let url = catalogURL(for: component, referrer: referrer) else { return nil }
            return (component, url)
        }
        var resolvedCarouselFromNetwork = false

        await withTaskGroup(of: CatalogFetchResult.self) { group in
            for (component, url) in requests {
                group.addTask {
                    CatalogFetchResult(
                        component: component,
                        data: await Self.fetchCatalogData(from: url)
                    )
                }
            }

            // Publish an independent component as soon as it finishes. A slow
            // video catalog can no longer hold a completed Hero or shortcut row.
            for await result in group {
                guard generation == loadGeneration else {
                    group.cancelAll()
                    return
                }

                if result.component == .carousel { resolvedCarouselFromNetwork = true }
                guard let data = result.data else { continue }
                do {
                    try applyCatalogData(data, component: result.component)
                    currentSnapshot.set(data, for: result.component)
                    await CatalogSnapshotStore.save(currentSnapshot)
                    isLoading = false
                    TemplateMediaMetrics.shared.markCatalogAvailable(source: "network")
                } catch {
                    // A malformed component must not replace the last valid
                    // snapshot or block the other independent components.
                }
            }
        }

        if resolvedCarouselFromNetwork, currentSnapshot.carouselData == nil {
            // Let section covers become the fallback after a failed first-ever
            // carousel request. An existing carousel snapshot stays visible.
            hasResolvedInitialCarouselLoad = true
        }
    }

    private func restore(_ snapshot: CatalogSnapshot) -> Bool {
        var restoredAnyComponent = false
        for component in CatalogComponent.allCases {
            guard let data = snapshot.data(for: component) else { continue }
            do {
                try applyCatalogData(data, component: component)
                restoredAnyComponent = true
            } catch {
                continue
            }
        }
        return restoredAnyComponent
    }

    private func applyCatalogData(_ data: Data, component: CatalogComponent) throws {
        switch component {
        case .videoSections:
            videoSections = try decodedSections(from: data, generationKind: .video)
        case .imageSections:
            imageSections = try decodedSections(from: data, generationKind: .image)
        case .carousel:
            let carousels = try decodedCarousels(from: data)
            homeCarouselEntries = carousels.entries[.home] ?? []
            photoCarouselEntries = carousels.entries[.photo] ?? []
            videoCarouselEntries = carousels.entries[.video] ?? []
            homeHeroOffer = carousels.homeHeroOffer
            homeCreditPurchasePromotion = carousels.homeCreditPurchasePromotion
            homeBottomOffer = carousels.homeBottomOffer
            homeBottomCreditPurchasePromotion = carousels.homeBottomCreditPurchasePromotion
            hasResolvedInitialCarouselLoad = true
        case .quickActions:
            let fixedFeatures = try decodedQuickActions(from: data)
            homeQuickActions = fixedFeatures.quickActions
            creditPricing = fixedFeatures.creditPricing
        }
        prefetchInitialCovers()
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
        if let homeCreditPurchasePromotion {
            urls.insert(homeCreditPurchasePromotion.coverImageURL, at: 0)
        }
        if let homeBottomOffer { urls.append(homeBottomOffer.coverImageURL) }
        if let homeBottomCreditPurchasePromotion {
            urls.append(homeBottomCreditPurchasePromotion.coverImageURL)
        }
        TemplateMediaPreloader.prefetchImages(urls)
    }

    private func catalogURL(for component: CatalogComponent, referrer: String) -> URL? {
        let path: String
        var queryItems = [URLQueryItem]()
        switch component {
        case .videoSections, .imageSections:
            path = "functions/v1/get-feature-configs"
            queryItems = [
                URLQueryItem(name: "app_id", value: PhotoReviveAPIConfig.appID),
                URLQueryItem(
                    name: "menu",
                    value: component == .videoSections ? "video" : "image"
                ),
                URLQueryItem(name: "page_type", value: "default"),
                URLQueryItem(name: "limit", value: "20"),
                URLQueryItem(name: "referrer", value: referrer)
            ]
        case .carousel:
            path = "functions/v1/get-app-carousels"
            queryItems = [
                URLQueryItem(name: "app_id", value: PhotoReviveAPIConfig.appID),
                URLQueryItem(name: "referrer", value: referrer)
            ]
        case .quickActions:
            path = "functions/v1/get-app-fixed-features"
            queryItems = [URLQueryItem(name: "app_id", value: PhotoReviveAPIConfig.appID)]
        }

        var components = URLComponents(
            url: PhotoReviveAPIConfig.projectURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems
        return components?.url
    }

    private nonisolated static func fetchCatalogData(from url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func decodedSections(
        from data: Data,
        generationKind: TemplateGenerationKind
    ) throws -> [TemplateSection] {
        let payload = try JSONDecoder().decode(FeatureConfigResponse.self, from: data)
        return payload.sections
            .enumerated()
            .sorted { lhs, rhs in
                configuredOrder(lhs.element.sortOrder, rhs.element.sortOrder)
                    || (lhs.element.sortOrder == rhs.element.sortOrder && lhs.offset < rhs.offset)
            }
            .compactMap { $0.element.templateSection(generationKind: generationKind) }
    }

    private func decodedQuickActions(from data: Data) throws -> FixedFeatureLoadResult {
        let payload = try JSONDecoder().decode(RemoteFixedFeatureResponse.self, from: data)
        return FixedFeatureLoadResult(
            quickActions: payload.items.compactMap(\.quickAction),
            creditPricing: payload.creditPricing ?? .defaultValue
        )
    }

    private func decodedCarousels(from data: Data) throws -> CarouselLoadResult {
        let payload = try JSONDecoder().decode(RemoteCarouselResponse.self, from: data)
        let detailEntries: [(page: RemoteCarouselPage, entry: TemplateDetailEntry)] = payload.items.compactMap { item in
            guard item.normalizedPlacement == "hero" else { return nil }
            return item.page == .photo ? item.photoImageEntry : item.detailEntry
        }
        let mappedEntries = Dictionary(grouping: detailEntries, by: { $0.page })
            .mapValues { $0.map { $0.entry } }
        let offers = payload.items.compactMap(\.couponOffer)
        let creditPurchasePromotions = payload.items.compactMap(\.creditPurchasePromotion)
        return CarouselLoadResult(
            entries: mappedEntries,
            homeHeroOffer: offers.first { $0.placement == "hero" },
            homeCreditPurchasePromotion: creditPurchasePromotions.first { $0.placement == "hero" },
            homeBottomOffer: offers.first { $0.placement == "bottom_banner" },
            homeBottomCreditPurchasePromotion: creditPurchasePromotions.first {
                $0.placement == "bottom_banner"
            }
        )
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
        let creditPurchasePromotions = payload.items.compactMap(\.creditPurchasePromotion)
        return CarouselLoadResult(
            entries: mappedEntries,
            homeHeroOffer: offers.first { $0.placement == "hero" },
            homeCreditPurchasePromotion: creditPurchasePromotions.first { $0.placement == "hero" },
            homeBottomOffer: offers.first { $0.placement == "bottom_banner" },
            homeBottomCreditPurchasePromotion: creditPurchasePromotions.first {
                $0.placement == "bottom_banner"
            }
        )
    }

}

nonisolated private enum CatalogComponent: String, CaseIterable, Codable, Sendable {
    case videoSections
    case imageSections
    case carousel
    case quickActions
}

nonisolated private struct CatalogFetchResult: Sendable {
    let component: CatalogComponent
    let data: Data?
}

nonisolated private struct CatalogSnapshot: Codable, Sendable {
    let schemaVersion: Int
    let appID: String
    let referrer: String
    var savedAt: Date
    var videoSectionsData: Data?
    var imageSectionsData: Data?
    var carouselData: Data?
    var quickActionsData: Data?

    init(appID: String, referrer: String) {
        schemaVersion = 1
        self.appID = appID
        self.referrer = referrer
        savedAt = Date()
    }

    func data(for component: CatalogComponent) -> Data? {
        switch component {
        case .videoSections: videoSectionsData
        case .imageSections: imageSectionsData
        case .carousel: carouselData
        case .quickActions: quickActionsData
        }
    }

    mutating func set(_ data: Data, for component: CatalogComponent) {
        switch component {
        case .videoSections: videoSectionsData = data
        case .imageSections: imageSectionsData = data
        case .carousel: carouselData = data
        case .quickActions: quickActionsData = data
        }
        savedAt = Date()
    }
}

nonisolated private enum CatalogSnapshotStore {
    static func load(appID: String, referrer: String) async -> CatalogSnapshot? {
        await Task.detached(priority: .utility) {
            let url = snapshotURL(appID: appID, referrer: referrer)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let snapshot = try? decoder.decode(CatalogSnapshot.self, from: data),
                  snapshot.schemaVersion == 1 else {
                return nil
            }
            return snapshot
        }.value
    }

    static func save(_ snapshot: CatalogSnapshot) async {
        await Task.detached(priority: .utility) {
            do {
                let url = snapshotURL(appID: snapshot.appID, referrer: snapshot.referrer)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(snapshot).write(to: url, options: .atomic)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var mutableURL = url
                try? mutableURL.setResourceValues(values)
            } catch {
                // The network result remains valid even if this optional
                // bootstrap snapshot cannot be persisted.
            }
        }.value
    }

    private nonisolated static func snapshotURL(appID: String, referrer: String) -> URL {
        let safeAppID = appID
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
            .joined()
        let safeReferrer = String(
            referrer
                .unicodeScalars
                .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
                .joined()
                .prefix(80)
        )
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CMSCatalog", isDirectory: true)
            .appendingPathComponent("\(safeAppID)-\(safeReferrer)-catalog-v1.json")
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
    var homeCreditPurchasePromotion: CMSCreditPurchasePromotion?
    var homeBottomOffer: CMSCouponOffer?
    var homeBottomCreditPurchasePromotion: CMSCreditPurchasePromotion?
}

struct RemoteFixedFeatureResponse: Decodable {
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

enum RemoteFixedFeatureCoverType: String, Decodable {
    case image
    case video
}

struct RemoteFixedFeatureItem: Decodable {
    let featureKey: String
    let title: String
    let coverType: RemoteFixedFeatureCoverType
    let coverImageURL: String?
    let coverVideoURL: String?
    let generationTarget: RemoteFixedFeatureGenerationTarget?
    let generationTargets: [RemoteFixedFeatureGenerationTarget]?

    enum CodingKeys: String, CodingKey {
        case featureKey = "feature_key"
        case title
        case coverType = "cover_type"
        case coverImageURL = "cover_image_url"
        case coverVideoURL = "cover_video_url"
        case generationTarget = "generation_target"
        case generationTargets = "generation_targets"
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
        let targets = generationTargets?.map(\.value) ?? []
        return HomeQuickAction(
            feature: feature,
            title: title,
            item: item,
            generationTarget: generationTarget?.value,
            generationTargets: targets
        )
    }
}

struct RemoteFixedFeatureGenerationTarget: Decodable {
    let itemID: String
    let endpoint: String
    let modelType: String
    let modelID: String
    let estimatedCredits: Int
    let promptTemplate: String?

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case endpoint
        case modelType = "model_type"
        case modelID = "model_id"
        case estimatedCredits = "estimated_credits"
        case promptTemplate = "prompt_template"
    }

    var value: FeatureGenerationTarget {
        FeatureGenerationTarget(
            itemID: itemID,
            endpoint: endpoint,
            modelType: modelType,
            modelID: modelID,
            estimatedCredits: estimatedCredits,
            promptTemplate: promptTemplate
        )
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

    var normalizedContentKind: String {
        contentKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "template"
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
              normalizedContentKind == "coupon",
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

    var creditPurchasePromotion: CMSCreditPurchasePromotion? {
        guard page == .home,
              normalizedContentKind == "credit_purchase",
              coverType == .image,
              let coverImageURL = coverImageURL.flatMap(URL.init(string:)) else {
            return nil
        }

        return CMSCreditPurchasePromotion(
            id: id,
            placement: normalizedPlacement,
            coverImageURL: coverImageURL
        )
    }

    var detailEntry: (page: RemoteCarouselPage, entry: TemplateDetailEntry)? {
        guard normalizedContentKind == "template" else { return nil }
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
              normalizedContentKind == "template",
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
