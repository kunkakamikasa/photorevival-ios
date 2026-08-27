import SwiftUI

struct ContentView: View {
    private let startupPresentationsAllowed: Bool
    private let isReturningSession: Bool
    @AppStorage("isSubscribed") private var isSubscribed = false
    @AppStorage("isLoggedIn") private var storedIsLoggedIn = false
    @AppStorage("returningOfferLastPresentedDay") private var returningOfferLastPresentedDay = 0.0
    @State private var selectedTab: AppTab = .home
    @State private var selectedTemplateRoute: TemplateDetailRoute?
    @State private var showSettings = false
    @State private var fullScreenDestination: AppDestination?
    @AppStorage("limitedOfferLastPresentedDay") private var limitedOfferLastPresentedDay = 0.0
    @State private var showQuickCreator = false
    @State private var showHomeOfferBanner = true
    @StateObject private var accountStore = AppAccountStore.shared
    @State private var returningOffer: ReturningOfferVariant?
    @State private var hasEvaluatedReturningOffer = false
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

            Group {
                if selectedTab == .me {
                    MePage(
                        accountStore: accountStore,
                        onCreate: { showQuickCreator = true },
                        onSettings: { showSettings = true }
                    )
                } else {
                    DiscoveryPage(
                        tab: selectedTab,
                        videoSections: featureConfigStore.videoSections,
                        imageSections: featureConfigStore.imageSections,
                        homeSections: featureConfigStore.homeSections,
                        heroEntries: featureConfigStore.heroEntries(for: selectedTab),
                        homeQuickActions: featureConfigStore.homeQuickActions,
                        videoModeActions: featureConfigStore.videoModeActions,
                        homeHeroOffer: isSubscribed ? nil : featureConfigStore.homeHeroOffer,
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
                        onSummerOffer: { offer in
                            requireLogin { fullScreenDestination = .summerSale(offer) }
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
                }
            }
            .transition(.opacity)
        }
        .overlay(alignment: .bottom) {
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
                   !isSubscribed,
                   showHomeOfferBanner,
                   let offer = featureConfigStore.homeBottomOffer {
                    HomeDiscountBannerView(
                        imageURL: offer.coverImageURL,
                        onOpen: { requireLogin { fullScreenDestination = .summerSale(offer) } },
                        onClose: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showHomeOfferBanner = false
                            }
                        }
                    )
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
                    credits: creditsBinding
                )
            }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(credits: creditsBinding)
        }
        .fullScreenCover(isPresented: $showQuickCreator) {
            CreateFlowView(
                template: nil,
                creditPricing: featureConfigStore.creditPricing,
                credits: creditsBinding
            )
        }
        .fullScreenCover(item: $returningOffer) { variant in
            ReturningPromotionFlowView(variant: variant)
        }
        .preferredColorScheme(.light)
        .onAppear {
            trackSelectedTab()
        }
        .onChange(of: selectedTab) { _, _ in
            trackSelectedTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .adjustAttributionDidChange)) { _ in
            Task {
                await featureConfigStore.reloadAfterAttributionChange()
            }
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
                  !ProcessInfo.processInfo.arguments.contains("-showRewardsPreview") else { return }
#endif
            guard !hasEvaluatedReturningOffer else { return }
            hasEvaluatedReturningOffer = true

            let shouldPresent = ReturningOfferEligibility.shouldPresent(
                isReturningSession: isReturningSession,
                isSubscribed: isSubscribed,
                arguments: ProcessInfo.processInfo.arguments
            )

            guard shouldPresent else { return }
            let arguments = ProcessInfo.processInfo.arguments
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
            guard !Task.isCancelled else { return }
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
    case suggestion
    case login
    case fixedFeature(FixedFeature)

    var id: String {
        switch self {
        case .membership: "membership"
        case .summerSale(let offer): "summerSale-\(offer.id)"
        case .credits: "credits"
        case .suggestion: "suggestion"
        case .login: "login"
        case .fixedFeature(let feature): "fixedFeature-\(feature.id)"
        }
    }
}

#Preview {
    ContentView(featureConfigStore: FeatureConfigStore())
}
