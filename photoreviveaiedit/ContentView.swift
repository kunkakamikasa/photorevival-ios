import Combine
import SwiftUI

final class StartupPromotionSessionGate: ObservableObject {
    static let shared = StartupPromotionSessionGate()

    @Published private(set) var suppressesAutomaticPromotions = false
    private var hasClaimedAutomaticEvaluation = false

    func claimAutomaticEvaluation() -> Bool {
        guard !suppressesAutomaticPromotions,
              !hasClaimedAutomaticEvaluation else { return false }
        hasClaimedAutomaticEvaluation = true
        return true
    }

    func suppressAutomaticPromotionsForCurrentLaunch() {
        suppressesAutomaticPromotions = true
    }
}

struct ContentView: View {
    private let startupPresentationsAllowed: Bool
    private let isReturningSession: Bool
    @AppStorage("isSubscribed") private var isSubscribed = false
    @AppStorage("isLoggedIn") private var storedIsLoggedIn = false
    @AppStorage("returningOfferLastPresentedDay") private var returningOfferLastPresentedDay = 0.0
    @AppStorage("subscriberScratchCompletedCampaignVersion") private var subscriberScratchCompletedCampaignVersion = 0
    @State private var selectedTab: AppTab = .home
    @State private var selectedMeHistoryKind = MeHistoryKind.video
    @State private var selectedTemplateRoute: TemplateDetailRoute?
    @State private var showSettings = false
    @State private var fullScreenDestination: AppDestination?
    @AppStorage("limitedOfferLastPresentedDay") private var limitedOfferLastPresentedDay = 0.0
    @State private var showHomeOfferBanner = true
    @StateObject private var accountStore = AppAccountStore.shared
    @State private var returningOffer: ReturningOfferVariant?
    @State private var showSubscriberScratchOffer = false
    @ObservedObject private var startupPromotionGate = StartupPromotionSessionGate.shared
    @ObservedObject private var featureConfigStore: FeatureConfigStore
    @State private var pendingLoginAction: (() -> Void)?

    init(
        featureConfigStore: FeatureConfigStore,
        startupPresentationsAllowed: Bool = true,
        isReturningSession: Bool = false
    ) {
        _featureConfigStore = ObservedObject(wrappedValue: featureConfigStore)
        self.startupPresentationsAllowed = startupPresentationsAllowed
        self.isReturningSession = isReturningSession
    }

    var body: some View {
        ZStack {
            PaperTextureBackground()

            ZStack {
                if selectedTab == .me {
                    MePage(
                        kind: $selectedMeHistoryKind,
                        accountStore: accountStore,
                        onCreate: { feature in fullScreenDestination = .fixedFeature(feature) },
                        onSettings: { showSettings = true }
                    )
                    .transition(.opacity)
                } else {
                    DiscoveryPage(
                        tab: selectedTab,
                        videoSections: featureConfigStore.videoSections,
                        imageSections: featureConfigStore.imageSections,
                        homeSections: featureConfigStore.homeSections,
                        heroEntries: featureConfigStore.heroEntries(for: selectedTab),
                        homeQuickActions: featureConfigStore.homeQuickActions,
                        videoModeActions: featureConfigStore.videoModeActions,
                        homeHeroPromotion: CMSHomeHeroPromotion.visible(
                            isSubscribed: isSubscribed,
                            coupon: featureConfigStore.homeHeroOffer,
                            creditPurchase: featureConfigStore.homeCreditPurchasePromotion
                        ),
                        isLoadingTemplates: featureConfigStore.isLoading,
                        credits: accountStore.creditsBalance,
                        onSelectTemplate: { template in
                            AppAnalytics.templateSelected(
                                template,
                                source: "\(selectedTab.rawValue)_grid"
                            )
                            selectedTemplateRoute = TemplateDetailRoute(
                                item: template,
                                detailItems: featureConfigStore.browsingItems(
                                    for: template,
                                    on: selectedTab
                                )
                            )
                        },
                        onSelectCarousel: { entry in
                            if let feature = entry.fixedFeatureTarget {
                                AppAnalytics.fixedFeatureSelected(
                                    feature,
                                    source: "\(selectedTab.rawValue)_hero"
                                )
                                fullScreenDestination = .fixedFeature(feature)
                                return
                            }
                            guard let tryNowItem = entry.tryNowItem else { return }
                            AppAnalytics.templateSelected(
                                tryNowItem,
                                source: "\(selectedTab.rawValue)_hero"
                            )
                            selectedTemplateRoute = TemplateDetailRoute(
                                item: entry.displayItem,
                                detailItems: featureConfigStore.browsingItems(
                                    for: tryNowItem,
                                    on: selectedTab
                                ),
                                tryNowItem: tryNowItem,
                                tryNowItems: featureConfigStore.detailItems(for: tryNowItem)
                            )
                        },
                        onMembership: { fullScreenDestination = .membership },
                        onCredits: { requireLogin { fullScreenDestination = .credits } },
                        onGift: { requireLogin { fullScreenDestination = .credits } },
                        onSuggestion: { fullScreenDestination = .suggestion },
                        onHeroPromotion: { promotion in
                            switch promotion {
                            case .subscriptionCoupon(let offer):
                                requireLogin { fullScreenDestination = .summerSale(offer) }
                            case .creditPurchase:
                                requireLogin { fullScreenDestination = .creditStore }
                            }
                        },
                        isSubscribed: isSubscribed,
                        isLoggedIn: isLoggedIn,
                        onLogin: { requireLogin {} },
                        onFixedFeature: { feature in
                            AppAnalytics.fixedFeatureSelected(
                                feature,
                                source: "\(selectedTab.rawValue)_quick_action"
                            )
                            fullScreenDestination = .fixedFeature(feature)
                        }
                    )
                    // Keep each main tab's view tree independent. Reusing the same
                    // discovery tree makes SwiftUI animate Photo's conditional
                    // layout and section rows into Video's, which looks like mixed
                    // vertical and horizontal page movement.
                    .id(selectedTab)
                    .transition(.opacity)
                }
            }
            .transition(.opacity)
        }
        .overlay {
            GeometryReader { proxy in
                let bannerWidth = max(proxy.size.width - 36, 0)

                ZStack(alignment: .bottom) {
                    BottomTabBar(selection: $selectedTab) { tab in
                        guard tab == .me else {
                            withAnimation(.easeInOut(duration: 0.24)) { selectedTab = tab }
                            return
                        }
                        requireLogin {
                            withAnimation(.easeInOut(duration: 0.24)) { selectedTab = .me }
                        }
                    }

                    if selectedTab == .home,
                       showHomeOfferBanner,
                       let promotion = CMSHomeHeroPromotion.visible(
                            isSubscribed: isSubscribed,
                            coupon: featureConfigStore.homeBottomOffer,
                            creditPurchase: featureConfigStore.homeBottomCreditPurchasePromotion
                       ) {
                        HomeDiscountBannerView(
                            imageURL: promotion.coverImageURL,
                            onOpen: {
                                switch promotion {
                                case .subscriptionCoupon(let offer):
                                    requireLogin { fullScreenDestination = .summerSale(offer) }
                                case .creditPurchase:
                                    requireLogin { fullScreenDestination = .creditStore }
                                }
                            },
                            onClose: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showHomeOfferBanner = false
                                }
                            }
                        )
                        .frame(width: bannerWidth, height: bannerWidth / 3.0)
                        .padding(.bottom, 56)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
        .fullScreenCover(item: $selectedTemplateRoute) { route in
            TemplateDetailView(
                item: route.item,
                detailItems: route.detailItems,
                tryNowItem: route.tryNowItem,
                tryNowItems: route.tryNowItems,
                creationItemsProvider: { item in
                    featureConfigStore.detailItems(for: item)
                },
                recommendationItemsProvider: { item in
                    featureConfigStore.imageRecommendations(for: item)
                },
                photoToVideoGenerationTarget: featureConfigStore.homeQuickActions
                    .first { $0.feature == .photoToVideo }?
                    .generationTarget,
                creditPricing: featureConfigStore.creditPricing,
                credits: creditsBinding
            ) {
                selectedTemplateRoute = nil
            }
        }
        .fullScreenCover(item: $fullScreenDestination, onDismiss: handleDestinationDismissed) { destination in
            switch destination {
            case .membership:
                PaywallOfferFlowView(analyticsSource: "home_membership")
            case .summerSale(let offer):
                SummerSalePaywallView(offer: offer)
            case .credits:
                CreditCenterView(credits: creditsBinding, accountStore: accountStore)
            case .creditStore:
                CreditStoreView(
                    onClose: {
                        fullScreenDestination = nil
                    },
                    onPurchased: { _ in
                        fullScreenDestination = nil
                        Task {
                            await accountStore.refreshCredits()
                            await accountStore.refreshCreditTransactions()
                        }
                    }
                )
            case .suggestion:
                SuggestionView()
            case .login:
                SignInView {
                    fullScreenDestination = nil
                }
            case .fixedFeature(let feature):
                FixedFeatureView(
                    feature: feature,
                    quickActions: featureConfigStore.homeQuickActions,
                    creditPricing: featureConfigStore.creditPricing,
                    imageRecommendationItems: featureConfigStore.imageRecommendations(for: nil),
                    credits: creditsBinding
                )
            }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(credits: creditsBinding)
        }
        .fullScreenCover(item: $returningOffer) { variant in
            ReturningPromotionFlowView(variant: variant)
        }
        .fullScreenCover(isPresented: $showSubscriberScratchOffer) {
            SubscriberScratchOfferView(
                accountStore: accountStore,
                onRewardClaimed: {
                    subscriberScratchCompletedCampaignVersion = SubscriberScratchCampaign.version
                }
            )
        }
        .preferredColorScheme(.light)
        .onAppear {
            trackSelectedTab()
        }
        .onChange(of: selectedTab) { _, _ in
            trackSelectedTab()
        }
        .onChange(of: startupPromotionGate.suppressesAutomaticPromotions) { _, isSuppressed in
            guard isSuppressed else { return }
            returningOffer = nil
            showSubscriberScratchOffer = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .adjustAttributionDidChange)) { _ in
            Task {
                await featureConfigStore.reloadAfterAttributionChange()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appTabNavigationRequested)) { notification in
            guard let tab = notification.object as? AppTab else { return }
            if let rawHistoryKind = notification.userInfo?[Notification.Name.appTabNavigationHistoryKindKey] as? String,
               let historyKind = MeHistoryKind(rawValue: rawHistoryKind) {
                selectedMeHistoryKind = historyKind
            }
            navigateToMainTab(tab)
        }
        .task {
            await featureConfigStore.load()
        }
#if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-showSummerOfferPreview") else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            fullScreenDestination = .summerSale(Self.summerOfferPreview)
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-showRewardsPreview") else { return }
            await accountStore.prepareRewardSessionIfNeeded()
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            fullScreenDestination = .credits
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-showLimitedOfferPreview") else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            returningOffer = .limitedTime
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-showSuperPrizePreview") else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            returningOffer = .superPrize
        }
#endif
        .task(id: isLoggedIn) {
            if isLoggedIn {
                await accountStore.refreshAll()
            } else {
                accountStore.resetForSignedOutUser()
            }
        }
        .task(id: startupPresentationsAllowed) {
            guard startupPresentationsAllowed else { return }
#if DEBUG
            guard !ProcessInfo.processInfo.arguments.contains("-showSummerOfferPreview"),
                  !ProcessInfo.processInfo.arguments.contains("-showRewardsPreview"),
                  !ProcessInfo.processInfo.arguments.contains("-showLimitedOfferPreview"),
                  !ProcessInfo.processInfo.arguments.contains("-showSuperPrizePreview") else { return }
#endif
            guard startupPromotionGate.claimAutomaticEvaluation() else { return }

            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-resetSubscriberScratchEligibility") {
                subscriberScratchCompletedCampaignVersion = 0
            }
            if SubscriberScratchEligibility.shouldPresent(
                isReturningSession: isReturningSession,
                isSubscribed: isSubscribed,
                completedCampaignVersion: subscriberScratchCompletedCampaignVersion,
                arguments: arguments
            ) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled,
                      !startupPromotionGate.suppressesAutomaticPromotions else { return }
                showSubscriberScratchOffer = true
                return
            }

            let shouldPresent = ReturningOfferEligibility.shouldPresent(
                isReturningSession: isReturningSession,
                isSubscribed: isSubscribed,
                arguments: arguments
            )

            guard shouldPresent else { return }
            if arguments.contains("-resetReturningOfferEligibility") {
                returningOfferLastPresentedDay = 0
            }
            if arguments.contains("-resetLimitedOfferEligibility") {
                limitedOfferLastPresentedDay = 0
            }

            let forcePresentation = arguments.contains("-forceReturningOffer")
            guard forcePresentation || ReturningOfferEligibility.canPresent(
                lastPresentedDay: returningOfferLastPresentedDay
            ) else { return }

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  !startupPromotionGate.suppressesAutomaticPromotions else { return }
            returningOfferLastPresentedDay = LimitedOfferEligibility.dayKey(for: Date())
            let limitedTimeAvailable = LimitedOfferEligibility.canPresent(
                lastPresentedDay: limitedOfferLastPresentedDay
            )
            let selectedOffer = ReturningOfferVariant.select(
                arguments: arguments,
                limitedTimeAvailable: limitedTimeAvailable
            )
            if selectedOffer == .limitedTime {
                limitedOfferLastPresentedDay = LimitedOfferEligibility.dayKey(for: Date())
            }
            returningOffer = selectedOffer
        }
    }

    private var isLoggedIn: Bool {
        storedIsLoggedIn || ProcessInfo.processInfo.arguments.contains("-loggedIn")
    }

#if DEBUG
    private static let summerOfferPreview = CMSCouponOffer(
        id: "summer-offer-preview",
        placement: "hero",
        coverImageURL: URL(string: "https://example.com/summer-offer-preview.png")!,
        weeklyPlan: CMSCouponPlan(productID: "special_gift_weekly"),
        annualPlan: CMSCouponPlan(productID: "special_gift_yearly")
    )
#endif

    private var creditsBinding: Binding<Int> {
        Binding(
            get: { accountStore.creditsBalance },
            set: { _ in
                // The balance is server-authoritative. Legacy creation screens still
                // mutate this Binding, so discard that local value and reconcile.
                Task { await accountStore.refreshCredits() }
            }
        )
    }

    private func navigateToMainTab(_ tab: AppTab) {
        // A generation screen can be nested below a template detail/editor or
        // a fixed-feature cover. Clear both possible roots so the real app tab
        // becomes interactive again in a single tap.
        selectedTemplateRoute = nil
        fullScreenDestination = nil
        showSettings = false
        withAnimation(.easeInOut(duration: 0.24)) {
            selectedTab = tab
        }

        if tab == .me {
            Task { await accountStore.refreshHistory() }
        }
    }

    private func requireLogin(_ action: @escaping () -> Void) {
        guard !isLoggedIn else {
            action()
            return
        }

        pendingLoginAction = action
        AppAnalytics.authGateShown(source: "restricted_action")
        fullScreenDestination = .login
    }

    private func trackSelectedTab() {
        AppAnalytics.screen(
            "tab_\(selectedTab.rawValue)",
            className: "ContentView"
        )
    }

    private func handleDestinationDismissed() {
        if isLoggedIn, let action = pendingLoginAction {
            pendingLoginAction = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: action)
        } else if !isLoggedIn {
            pendingLoginAction = nil
        }

    }
}

private struct TemplateDetailRoute: Identifiable {
    let item: TemplateItem
    let detailItems: [TemplateItem]
    let tryNowItem: TemplateItem?
    let tryNowItems: [TemplateItem]?

    var id: String { item.id }

    init(
        item: TemplateItem,
        detailItems: [TemplateItem],
        tryNowItem: TemplateItem? = nil,
        tryNowItems: [TemplateItem]? = nil
    ) {
        self.item = item
        self.detailItems = detailItems
        self.tryNowItem = tryNowItem
        self.tryNowItems = tryNowItems
    }
}

private enum AppDestination: Identifiable {
    case membership
    case summerSale(CMSCouponOffer)
    case credits
    case creditStore
    case suggestion
    case login
    case fixedFeature(FixedFeature)

    var id: String {
        switch self {
        case .membership: "membership"
        case .summerSale(let offer): "summerSale-\(offer.id)"
        case .credits: "credits"
        case .creditStore: "creditStore"
        case .suggestion: "suggestion"
        case .login: "login"
        case .fixedFeature(let feature): "fixedFeature-\(feature.id)"
        }
    }
}

#Preview {
    ContentView(featureConfigStore: FeatureConfigStore())
}
