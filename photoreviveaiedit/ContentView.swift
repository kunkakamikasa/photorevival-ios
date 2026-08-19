import SwiftUI

struct ContentView: View {
    private let startupPresentationsAllowed: Bool
    @AppStorage("isSubscribed") private var isSubscribed = false
    @AppStorage("isLoggedIn") private var storedIsLoggedIn = false
    @AppStorage("hasOpenedMainExperience") private var hasOpenedMainExperience = false
    @AppStorage("returningOfferLastPresentedDay") private var returningOfferLastPresentedDay = 0.0
    @State private var selectedTab: AppTab = .home
    @State private var selectedTemplate: TemplateItem?
    @State private var showSettings = false
    @State private var fullScreenDestination: AppDestination?
    @State private var postDismissAction: PostDismissAction?
    @State private var showLimitedOfferPopup = false
    @AppStorage("limitedOfferLastPresentedDay") private var limitedOfferLastPresentedDay = 0.0
    @State private var showQuickCreator = false
    @State private var showHomeOfferBanner = true
    @State private var credits = 0
    @State private var returningOffer: ReturningOfferVariant?
    @State private var hasEvaluatedReturningOffer = false
    @StateObject private var featureConfigStore = FeatureConfigStore()
    @State private var selectedTemplateGroup: [TemplateItem] = []

    init(startupPresentationsAllowed: Bool = true) {
        self.startupPresentationsAllowed = startupPresentationsAllowed
    }

    var body: some View {
        ZStack {
            PaperTextureBackground()

            Group {
                if selectedTab == .me {
                    MePage(
                        onCreate: { showQuickCreator = true },
                        onSettings: { showSettings = true }
                    )
                } else {
                    DiscoveryPage(
                        tab: selectedTab,
                        videoSections: featureConfigStore.videoSections,
                        heroItems: featureConfigStore.heroItems,
                        isLoadingTemplates: featureConfigStore.isLoading,
                        credits: credits,
                        onSelectTemplate: { template in
                            selectedTemplateGroup = featureConfigStore.detailItems(for: template)
                            selectedTemplate = template
                        },
                        onMembership: { fullScreenDestination = .membership },
                        onCredits: { fullScreenDestination = .credits },
                        onGift: { fullScreenDestination = .credits },
                        onSuggestion: { fullScreenDestination = .suggestion },
                    onSummerOffer: { fullScreenDestination = .summerSale },
                    isSubscribed: isSubscribed,
                    onLogin: { fullScreenDestination = .login },
                    onFixedFeature: { feature in
                        fullScreenDestination = .fixedFeature(feature)
                    }
                )
                }
            }
            .transition(.opacity)
        }
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                BottomTabBar(selection: $selectedTab)

                if selectedTab == .home && showHomeOfferBanner {
                    HomeDiscountBannerView(
                        onOpen: { fullScreenDestination = .summerSale },
                        onClose: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showHomeOfferBanner = false
                            }
                        }
                    )
                    .padding(.bottom, 68)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .overlay {
            if showLimitedOfferPopup {
                LimitedTimeOfferPopup {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showLimitedOfferPopup = false
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(10)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
        .fullScreenCover(item: $selectedTemplate) { template in
            TemplateDetailView(
                item: template,
                detailItems: selectedTemplateGroup,
                credits: $credits
            ) {
                selectedTemplate = nil
            }
        }
        .fullScreenCover(item: $fullScreenDestination, onDismiss: handleDestinationDismissed) { destination in
            switch destination {
            case .membership:
                MembershipPaywallView {
                    postDismissAction = .limitedOffer
                    fullScreenDestination = nil
                }
            case .superPrize:
                SuperPrizeOfferView {
                    postDismissAction = .limitedOffer
                    fullScreenDestination = nil
                }
            case .summerSale:
                SummerSalePaywallView()
            case .credits:
                CreditCenterView(credits: $credits)
            case .suggestion:
                SuggestionView()
            case .login:
                SignInView()
            case .fixedFeature(let feature):
                FixedFeatureView(feature: feature, credits: $credits)
            }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(credits: $credits)
        }
        .fullScreenCover(isPresented: $showQuickCreator) {
            CreateFlowView(template: nil, credits: $credits)
        }
        .fullScreenCover(item: $returningOffer) { variant in
            switch variant {
            case .familyExclusive:
                ReturningUserOfferFlowView()
            case .superPrize:
                SuperPrizeOfferView {
                    returningOffer = nil
                }
            }
        }
        .preferredColorScheme(.light)
        .task {
            await featureConfigStore.load()
        }
        .task(id: startupPresentationsAllowed) {
            guard startupPresentationsAllowed else { return }
            guard !hasEvaluatedReturningOffer else { return }
            hasEvaluatedReturningOffer = true

            let shouldPresent = ReturningOfferEligibility.shouldPresent(
                hasOpenedMainExperience: hasOpenedMainExperience,
                isSubscribed: isSubscribed,
                isLoggedIn: isLoggedIn,
                arguments: ProcessInfo.processInfo.arguments
            )
            hasOpenedMainExperience = true

            guard shouldPresent else { return }
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-resetReturningOfferEligibility") {
                returningOfferLastPresentedDay = 0
            }

            let forcePresentation = arguments.contains("-forceReturningOffer")
            guard forcePresentation || ReturningOfferEligibility.canPresent(
                lastPresentedDay: returningOfferLastPresentedDay
            ) else { return }

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            returningOfferLastPresentedDay = LimitedOfferEligibility.dayKey(for: Date())
            returningOffer = ReturningOfferVariant.select(arguments: arguments)
        }
    }

    private var isLoggedIn: Bool {
        storedIsLoggedIn || ProcessInfo.processInfo.arguments.contains("-loggedIn")
    }

    private func handleDestinationDismissed() {
        let action = postDismissAction
        postDismissAction = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            switch action {
            case .superPrize:
                fullScreenDestination = .superPrize
            case .limitedOffer:
                presentLimitedOfferIfEligible()
            case nil:
                break
            }
        }
    }

    private func presentLimitedOfferIfEligible() {
        guard !isSubscribed else { return }

        let arguments = ProcessInfo.processInfo.arguments
        let forcePresentation = arguments.contains("-forceLimitedOffer")
        if arguments.contains("-resetLimitedOfferEligibility") {
            limitedOfferLastPresentedDay = 0
        }

        let today = LimitedOfferEligibility.dayKey(for: Date())
        guard forcePresentation || LimitedOfferEligibility.canPresent(lastPresentedDay: limitedOfferLastPresentedDay) else { return }

        limitedOfferLastPresentedDay = today
        withAnimation(.easeOut(duration: 0.22)) {
            showLimitedOfferPopup = true
        }
    }
}

private enum AppDestination: Identifiable {
    case membership
    case superPrize
    case summerSale
    case credits
    case suggestion
    case login
    case fixedFeature(FixedFeature)

    var id: String {
        switch self {
        case .membership: "membership"
        case .superPrize: "superPrize"
        case .summerSale: "summerSale"
        case .credits: "credits"
        case .suggestion: "suggestion"
        case .login: "login"
        case .fixedFeature(let feature): "fixedFeature-\(feature.id)"
        }
    }
}

private enum PostDismissAction {
    case superPrize
    case limitedOffer
}

#Preview {
    ContentView()
}
