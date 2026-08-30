import SwiftUI

enum StartupAnimationPolicy {
    static let minimumDisplayNanoseconds: UInt64 = 4_000_000_000

    static func shouldKeepShowing(
        minimumDurationElapsed: Bool,
        isFirstInstall: Bool,
        hasUsableNetworkPath: Bool,
        isInitialPermissionFlowPending: Bool = false
    ) -> Bool {
        !minimumDurationElapsed
            || (isFirstInstall && !hasUsableNetworkPath)
            || isInitialPermissionFlowPending
    }

    static func canBeginExternalRequests(
        sceneIsActive: Bool,
        startupVideoIsReady: Bool,
        skipsStartupAnimation: Bool
    ) -> Bool {
        sceneIsActive && (startupVideoIsReady || skipsStartupAnimation)
    }
}

enum OnboardingGuideSwipeDirection: Equatable {
    case previous
    case next
}

enum OnboardingGuideSwipePolicy {
    private static let minimumHorizontalDistance: CGFloat = 44

    static func direction(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> OnboardingGuideSwipeDirection? {
        let projectedTranslation = abs(predictedEndTranslation.width) > abs(translation.width)
            ? predictedEndTranslation
            : translation

        guard abs(projectedTranslation.width) >= minimumHorizontalDistance,
              abs(projectedTranslation.width) > abs(projectedTranslation.height) else {
            return nil
        }

        return projectedTranslation.width < 0 ? .next : .previous
    }
}

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var appOpenAdManager = AppOpenAdManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("isSubscribed") private var isSubscribed = false
    @AppStorage("limitedOfferLastPresentedDay") private var limitedOfferLastPresentedDay = 0.0
    @StateObject private var trackingAuthorization = TrackingAuthorizationManager()
    @StateObject private var networkAccessMonitor = NetworkAccessMonitor()
    @StateObject private var featureConfigStore = FeatureConfigStore()
    @State private var completedOnboardingThisSession = false
    @State private var showInitialMembership = false
    @State private var initialMembershipWasClosed = false
    @State private var initialFollowUpOffer: PaywallFollowUpOffer?
    @State private var isShowingStartupVideo = true
    @State private var startupVideoIsReady = false
#if DEBUG
    @AppStorage("debugTestUserStateOverrideEnabled") private var debugStateOverrideEnabled = false
#endif

    private let arguments = ProcessInfo.processInfo.arguments

    private var shouldShowOnboarding: Bool {
        guard !completedOnboardingThisSession else { return false }
        if arguments.contains("-forceOnboarding") { return true }
        if arguments.contains("-skipOnboarding") { return false }
        return !hasCompletedOnboarding
    }

    private var shouldKeepShowingStartupAnimation: Bool {
        StartupAnimationPolicy.shouldKeepShowing(
            minimumDurationElapsed: !isShowingStartupVideo,
            isFirstInstall: shouldShowOnboarding,
            hasUsableNetworkPath: networkAccessMonitor.hasUsableNetworkPath,
            // Keep this exact player view alive until the first permission flow
            // has actually completed. Scene phase alone is insufficient because
            // iOS can move a long-lived system sheet between inactive/background.
            isInitialPermissionFlowPending: startupVideoIsReady
                && !trackingAuthorization.hasFinishedInitialRequest
        )
    }

    private var canBeginExternalRequests: Bool {
        StartupAnimationPolicy.canBeginExternalRequests(
            sceneIsActive: scenePhase == .active,
            startupVideoIsReady: startupVideoIsReady,
            skipsStartupAnimation: arguments.contains("-skipStartupAnimation")
        )
    }

    private var configuredOfferProductIDs: [String] {
        [featureConfigStore.homeHeroOffer, featureConfigStore.homeBottomOffer]
            .compactMap { $0 }
            .flatMap { [$0.weeklyPlan.productID, $0.annualPlan.productID] }
    }

    var body: some View {
        ZStack {
#if DEBUG
            if arguments.contains("-showSuperPrizePreview") {
                SuperPrizeOfferView(onClose: {})
            } else {
                appContent
            }
#else
            appContent
#endif
        }
        .fullScreenCover(isPresented: $showInitialMembership, onDismiss: handleInitialMembershipDismissed) {
            MembershipPaywallView(
                showsFirstLaunchVideoBackground: true,
                analyticsSource: "onboarding",
                onClose: {
                    initialMembershipWasClosed = true
                    showInitialMembership = false
                }
            )
        }
        .fullScreenCover(item: $initialFollowUpOffer) { offer in
            PaywallFollowUpOfferView(offer: offer)
        }
#if DEBUG
        .background {
            DebugTestWindowInstaller()
                .frame(width: 0, height: 0)
        }
#endif
        .onReceive(NotificationCenter.default.publisher(for: .adjustAttributionDidChange)) { _ in
            Task {
                await PhotoReviveAuthClient.shared.bindAdjustAttributionIfAvailable()
            }
        }
        .task(id: canBeginExternalRequests) {
            guard canBeginExternalRequests else { return }
            // Firebase, Meta activation, CMS loading, consent, and ATT can all
            // cause first-install system prompts. Start them only after the
            // bundled launch video has rendered a real frame behind the UI.
            StartupServiceBootstrap.configureIfNeeded()
            StartupAppActivationGate.shared.startupVisualDidBecomeReady()

            // Start CMS and cover warming before any permission flow. This is
            // useful work hidden by the startup animation and system prompt.
            let featureLoadTask = Task {
                await featureConfigStore.load()
            }
            // Ask with Apple's native ATT sheet first. Google UMP is deliberately
            // loaded only after ATT is resolved so its AdMob-hosted IDFA
            // explainer cannot add an extra conversion-blocking screen.
            await trackingAuthorization.requestAuthorizationIfNeeded()
            guard !Task.isCancelled else { return }
            if AppOpenAdConfiguration.isAdvertisingEnabled,
               AppOpenAdConfiguration.hasValidApplicationID {
                _ = await AdvertisingConsentManager.shared.prepareForAdRequests()
            }
            guard !Task.isCancelled else { return }
#if DEBUG
            if !debugStateOverrideEnabled {
                isSubscribed = await SubscriptionPurchaseService.hasActiveStoreEntitlement()
            }
#else
            isSubscribed = await SubscriptionPurchaseService.hasActiveStoreEntitlement()
#endif
            AppAnalytics.updateSubscription(isSubscribed: isSubscribed)
            AdjustService.shared.startIfNeeded(
                externalDeviceID: PhotoReviveAuthClient.shared.currentUserID
            )
            await PhotoReviveAuthClient.shared.bindAdjustAttributionIfAvailable()
            await featureLoadTask.value
        }
        .task(id: networkAccessMonitor.hasUsableNetworkPath) {
            guard networkAccessMonitor.hasUsableNetworkPath else { return }
            // Do not wait for the permission flow or the four-second minimum.
            // Use that hidden time to warm every known App Store price.
            await StoreProductPriceStore.shared.preloadKnownProducts()
            await StoreProductPriceStore.shared.load(productIDs: configuredOfferProductIDs)
        }
        .task(id: configuredOfferProductIDs) {
            guard networkAccessMonitor.hasUsableNetworkPath else { return }
            await StoreProductPriceStore.shared.load(productIDs: configuredOfferProductIDs)
        }
        .task {
            if arguments.contains("-skipStartupAnimation") {
                isShowingStartupVideo = false
                return
            }

            try? await Task.sleep(nanoseconds: StartupAnimationPolicy.minimumDisplayNanoseconds)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                isShowingStartupVideo = false
            }
        }
        .environment(\.homeSubscriptionCouponOffer, featureConfigStore.homeHeroOffer)
    }

    @ViewBuilder
    private var appContent: some View {
        if shouldKeepShowingStartupAnimation || appOpenAdManager.isBlockingLaunchContent {
            StartupAnimationView {
                startupVideoIsReady = true
            }
                .transition(.opacity)
        } else if shouldShowOnboarding {
            LaunchExperienceView {
                completeOnboarding()
            }
            .transition(.opacity)
        } else {
            ContentView(
                featureConfigStore: featureConfigStore,
                startupPresentationsAllowed: trackingAuthorization.hasFinishedInitialRequest
                    && !appOpenAdManager.didPresentAdForCurrentLaunch,
                isReturningSession: hasCompletedOnboarding && !completedOnboardingThisSession
            )
                .transition(.opacity)
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        withAnimation(.easeInOut(duration: 0.35)) {
            completedOnboardingThisSession = true
        }
        initialMembershipWasClosed = false
        showInitialMembership = true
    }

    private func handleInitialMembershipDismissed() {
        guard initialMembershipWasClosed, !isSubscribed else {
            initialMembershipWasClosed = false
            return
        }
        initialMembershipWasClosed = false

        Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !isSubscribed else { return }

            if arguments.contains("-resetLimitedOfferEligibility") {
                limitedOfferLastPresentedDay = 0
            }
            let limitedTimeAvailable = LimitedOfferEligibility.canPresent(
                lastPresentedDay: limitedOfferLastPresentedDay
            )
            let offer = PaywallFollowUpOffer.select(
                limitedTimeAvailable: limitedTimeAvailable
            )
            if offer == .limitedTime {
                limitedOfferLastPresentedDay = LimitedOfferEligibility.dayKey(for: Date())
            }
            initialFollowUpOffer = offer
        }
    }
}

private struct LaunchExperienceView: View {
    let onComplete: () -> Void
    @State private var currentPage = LaunchPage.welcome.rawValue

    private var page: LaunchPage {
        LaunchPage(rawValue: currentPage) ?? .welcome
    }

    var body: some View {
        ZStack {
            LaunchBackgroundMedia(
                videoName: page.videoName,
                mediaAspectRatio: page.mediaAspectRatio
            )
            .allowsHitTesting(false)

            if page != .welcome {
                LinearGradient(
                    stops: page.gradientStops,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            switch page {
            case .welcome:
                WelcomeVideoContinueHitTarget(onContinue: advance)
            case .restore, .pet, .fusion:
                GuideOverlay(
                    page: page,
                    onContinue: advance,
                    onSwipe: moveGuidePage
                )
            }
        }
        .id(page.rawValue)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.38), value: currentPage)
        .preferredColorScheme(page.colorScheme)
        .task(id: currentPage) {
            AppAnalytics.onboardingStepViewed(
                name: page.analyticsName,
                index: page.rawValue
            )
        }
    }

    private func advance() {
        if currentPage < LaunchPage.fusion.rawValue {
            withAnimation(.easeInOut(duration: 0.38)) {
                currentPage += 1
            }
        } else {
            AppAnalytics.onboardingCompleted()
            onComplete()
        }
    }

    private func moveGuidePage(_ direction: OnboardingGuideSwipeDirection) {
        let nextPage = switch direction {
        case .previous:
            max(currentPage - 1, LaunchPage.restore.rawValue)
        case .next:
            min(currentPage + 1, LaunchPage.fusion.rawValue)
        }

        guard nextPage != currentPage else { return }
        withAnimation(.easeInOut(duration: 0.38)) {
            currentPage = nextPage
        }
    }
}

private enum LaunchPage: Int {
    case welcome
    case restore
    case pet
    case fusion

    var analyticsName: String {
        switch self {
        case .welcome: "welcome"
        case .restore: "restore"
        case .pet: "pet"
        case .fusion: "fusion"
        }
    }

    var videoName: String {
        switch self {
        case .welcome: "OnboardingWelcomeVideo"
        case .restore: "OnboardingRestoreVideo"
        case .pet: "OnboardingPetVideo"
        case .fusion: "OnboardingFusionVideo"
        }
    }

    /// The three guide videos are authored at 9:16. Fitting that exact canvas
    /// to the screen width preserves the side margins baked into the footage;
    /// any extra height on taller devices is absorbed by the black lower area.
    var mediaAspectRatio: CGFloat? {
        switch self {
        case .welcome: nil
        case .restore, .pet, .fusion: 9.0 / 16.0
        }
    }

    var title: String {
        switch self {
        case .restore: "Bring Memories to Life"
        case .pet: "See Your Pet Again"
        case .fusion: "Bring Your\nFamily Together"
        case .welcome: ""
        }
    }

    var subtitle: String {
        switch self {
        case .restore: "With Restore & Photo to Video"
        case .pet: "With Templates"
        case .fusion: "With Fusion"
        case .welcome: ""
        }
    }

    var guideIndex: Int {
        switch self {
        case .restore: 0
        case .pet: 1
        case .fusion: 2
        case .welcome: 0
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .welcome, .restore: .dark
        case .pet, .fusion: .light
        }
    }

    var gradientStops: [Gradient.Stop] {
        switch self {
        case .welcome:
            [
                .init(color: .clear, location: 0.43),
                .init(color: .black.opacity(0.72), location: 0.58),
                .init(color: .black, location: 0.74)
            ]
        case .restore, .pet:
            [
                .init(color: .clear, location: 0.54),
                .init(color: .black.opacity(0.58), location: 0.72),
                .init(color: .black, location: 0.94)
            ]
        case .fusion:
            [
                .init(color: .clear, location: 0.47),
                .init(color: .black.opacity(0.62), location: 0.68),
                .init(color: .black, location: 0.94)
            ]
        }
    }
}

private struct StartupAnimationView: View {
    let onReadyForDisplay: () -> Void

    var body: some View {
        LaunchBackgroundMedia(
            videoName: "OnboardingLaunchVideo",
            posterImageName: "StartupVideoPoster",
            preservesPlaybackWhenInactive: true,
            onReadyForDisplay: onReadyForDisplay
        )
        .accessibilityLabel("Photo Revival startup animation")
        .preferredColorScheme(.light)
    }
}

private struct LaunchBackgroundMedia: View {
    let videoName: String
    var mediaAspectRatio: CGFloat? = nil
    var posterImageName: String? = nil
    var preservesPlaybackWhenInactive = false
    var onReadyForDisplay: (() -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if let mediaAspectRatio {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    backgroundLayer

                    LoopingVideoView(
                        resourceName: videoName,
                        videoAspectRatio: mediaAspectRatio,
                        preservesPlaybackWhenInactive: preservesPlaybackWhenInactive,
                        onReadyForDisplay: onReadyForDisplay
                    )
                }
            }
            .ignoresSafeArea()
        } else {
            mediaLayers
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
        }
    }

    private var mediaLayers: some View {
        ZStack {
            backgroundLayer

            LoopingVideoView(
                resourceName: videoName,
                preservesPlaybackWhenInactive: preservesPlaybackWhenInactive,
                onReadyForDisplay: onReadyForDisplay
            )
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let posterImageName {
            Image(posterImageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            Color.black
        }
    }
}

private struct WelcomeVideoContinueHitTarget: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            Button(action: onContinue) {
                RoundedRectangle(cornerRadius: 12)
                    // Keep the button artwork authored into the welcome video,
                    // but render a real surface so SwiftUI does not optimize the
                    // completely clear label out of manual hit testing.
                    .fill(Color.white.opacity(0.001))
                    .frame(
                        width: max(proxy.size.width - 32, 0),
                        height: 72
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.890)
            .zIndex(1)
            .accessibilityLabel("Continue")
            .accessibilityIdentifier("onboarding-continue")
        }
    }
}

private struct GuideOverlay: View {
    let page: LaunchPage
    let onContinue: () -> Void
    let onSwipe: (OnboardingGuideSwipeDirection) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    Text(page.title)
                        .font(.system(size: 29, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .lineSpacing(1)

                    Text(page.subtitle)
                        .font(.system(size: 20, weight: .regular))
                        .padding(.top, 8)

                    OnboardingPageDots(selection: page.guideIndex)
                        .padding(.top, 18)
                }
                .foregroundStyle(.white)
                .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height * 0.797 - 24
                )

                OnboardingContinueButton(action: onContinue)
                    .padding(.horizontal, 20)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.890)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 16)
                    .onEnded { value in
                        guard let direction = OnboardingGuideSwipePolicy.direction(
                            translation: value.translation,
                            predictedEndTranslation: value.predictedEndTranslation
                        ) else { return }
                        onSwipe(direction)
                    }
            )
        }
    }
}

private struct OnboardingPageDots: View {
    let selection: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == selection ? .white : .white.opacity(0.43))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel("Guide page \(selection + 1) of 3")
    }
}

private struct OnboardingContinueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text("Continue")
                    .font(.system(size: 21, weight: .bold))

                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 23, weight: .semibold))
                }
                .padding(.horizontal, 20)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(red: 0.84, green: 0.29, blue: 0.24), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(TemplatePressStyle())
        .accessibilityIdentifier("onboarding-continue")
    }
}
