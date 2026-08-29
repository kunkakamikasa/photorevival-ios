import SwiftUI

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("isSubscribed") private var isSubscribed = false
    @AppStorage("limitedOfferLastPresentedDay") private var limitedOfferLastPresentedDay = 0.0
    @StateObject private var trackingAuthorization = TrackingAuthorizationManager()
    @StateObject private var featureConfigStore = FeatureConfigStore()
    @State private var completedOnboardingThisSession = false
    @State private var showInitialMembership = false
    @State private var initialMembershipWasClosed = false
    @State private var initialFollowUpOffer: PaywallFollowUpOffer?
    @State private var isShowingStartupVideo = true
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
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // Start CMS and cover warming before any permission flow. This is
            // the useful work hidden by the three-second startup animation.
            let featureLoadTask = Task {
                await featureConfigStore.load()
            }
#if DEBUG
            if !debugStateOverrideEnabled {
                isSubscribed = await SubscriptionPurchaseService.hasActiveStoreEntitlement()
            }
#else
            isSubscribed = await SubscriptionPurchaseService.hasActiveStoreEntitlement()
#endif
            AppAnalytics.updateSubscription(isSubscribed: isSubscribed)
            await trackingAuthorization.requestAuthorizationIfNeeded()
            guard !Task.isCancelled else { return }
            AdjustService.shared.startIfNeeded(
                externalDeviceID: PhotoReviveAuthClient.shared.currentUserID
            )
            await PhotoReviveAuthClient.shared.bindAdjustAttributionIfAvailable()
            await featureLoadTask.value
        }
        .task {
            if arguments.contains("-skipStartupAnimation") {
                isShowingStartupVideo = false
                return
            }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                isShowingStartupVideo = false
            }
        }
        .environment(\.homeSubscriptionCouponOffer, featureConfigStore.homeHeroOffer)
    }

    @ViewBuilder
    private var appContent: some View {
        if isShowingStartupVideo {
            StartupAnimationView()
                .transition(.opacity)
        } else if shouldShowOnboarding {
            LaunchExperienceView {
                completeOnboarding()
            }
            .transition(.opacity)
        } else {
            ContentView(
                featureConfigStore: featureConfigStore,
                startupPresentationsAllowed: trackingAuthorization.hasFinishedInitialRequest,
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
                GuideOverlay(page: page, onContinue: advance)
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
    var body: some View {
        LaunchBackgroundMedia(
            videoName: "OnboardingLaunchVideo"
        )
        .accessibilityLabel("Photo Revival startup animation")
        .preferredColorScheme(.light)
    }
}

private struct LaunchBackgroundMedia: View {
    let videoName: String
    var mediaAspectRatio: CGFloat? = nil

    @ViewBuilder
    var body: some View {
        if let mediaAspectRatio {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    // Stay image-free until AVPlayerLayer is ready. A bundled
                    // poster here would briefly expose stale onboarding art.
                    Color.black

                    LoopingVideoView(
                        resourceName: videoName,
                        videoAspectRatio: mediaAspectRatio
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
            // Match the system launch color without introducing a poster frame.
            Color.black

            LoopingVideoView(resourceName: videoName)
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
