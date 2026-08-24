import SwiftUI

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var trackingAuthorization = TrackingAuthorizationManager()
    @State private var completedOnboardingThisSession = false
    @State private var showInitialMembership = false
    @State private var canRequestTrackingAuthorization = false

    private let arguments = ProcessInfo.processInfo.arguments

    private var shouldShowOnboarding: Bool {
        guard !completedOnboardingThisSession else { return false }
        if arguments.contains("-forceOnboarding") { return true }
        if arguments.contains("-skipOnboarding") { return false }
        return !hasCompletedOnboarding
    }

    var body: some View {
        ZStack {
            if shouldShowOnboarding {
                LaunchExperienceView {
                    completeOnboarding()
                }
                .transition(.opacity)
            } else {
                ContentView(
                    startupPresentationsAllowed: trackingAuthorization.hasFinishedInitialRequest
                )
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $showInitialMembership, onDismiss: {
            canRequestTrackingAuthorization = true
        }) {
            MembershipPaywallView()
        }
        .onAppear {
            if !shouldShowOnboarding {
                canRequestTrackingAuthorization = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .adjustAttributionDidChange)) { _ in
            Task {
                await PhotoReviveAuthClient.shared.bindAdjustAttributionIfAvailable()
            }
        }
        .task(id: trackingRequestContext) {
            guard trackingRequestContext.canRequest else { return }
            await trackingAuthorization.requestAuthorizationIfNeeded()
            guard !Task.isCancelled, scenePhase == .active else { return }
            AdjustService.shared.startIfNeeded(
                externalDeviceID: PhotoReviveAuthClient.shared.currentUserID
            )
            await PhotoReviveAuthClient.shared.bindAdjustAttributionIfAvailable()
        }
    }

    private var trackingRequestContext: TrackingRequestContext {
        TrackingRequestContext(
            canRequest: canRequestTrackingAuthorization
                && scenePhase == .active
                && !showInitialMembership
        )
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        withAnimation(.easeInOut(duration: 0.35)) {
            completedOnboardingThisSession = true
        }
        showInitialMembership = true
    }
}

private struct TrackingRequestContext: Equatable {
    let canRequest: Bool
}

private struct LaunchExperienceView: View {
    let onComplete: () -> Void
    @State private var currentPage = LaunchPage.effect.rawValue

    private var page: LaunchPage {
        LaunchPage(rawValue: currentPage) ?? .effect
    }

    var body: some View {
        ZStack {
            LaunchBackgroundMedia(imageName: page.imageName, videoName: page.videoName)

            if page != .effect {
                LinearGradient(
                    stops: page.gradientStops,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            switch page {
            case .effect:
                Color.clear
                    .accessibilityLabel("Photo Revive effect preview")
            case .welcome:
                WelcomeMarketingOverlay(onContinue: advance)
            case .restore, .pet, .fusion:
                GuideOverlay(page: page, onContinue: advance)
            }
        }
        .id(page.rawValue)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.38), value: currentPage)
        .preferredColorScheme(page.colorScheme)
        .task(id: currentPage) {
            guard page == .effect else { return }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, currentPage == LaunchPage.effect.rawValue else { return }
            advance()
        }
    }

    private func advance() {
        if currentPage < LaunchPage.fusion.rawValue {
            withAnimation(.easeInOut(duration: 0.38)) {
                currentPage += 1
            }
        } else {
            onComplete()
        }
    }
}

private enum LaunchPage: Int {
    case effect
    case welcome
    case restore
    case pet
    case fusion

    var imageName: String {
        switch self {
        case .effect: "OnboardingEffectBackground"
        case .welcome: "OnboardingWelcomeBackground"
        case .restore: "OnboardingRestoreBackground"
        case .pet: "OnboardingPetBackground"
        case .fusion: "OnboardingFusionBackground"
        }
    }

    var videoName: String? {
        switch self {
        case .effect: "onboarding_launch"
        case .welcome, .restore, .pet, .fusion: nil
        }
    }

    var title: String {
        switch self {
        case .restore: "Bring Memories to Life"
        case .pet: "See Your Pet Again"
        case .fusion: "Bring Your\nFamily Together"
        case .effect, .welcome: ""
        }
    }

    var subtitle: String {
        switch self {
        case .restore: "With Restore & Photo to Video"
        case .pet: "With Templates"
        case .fusion: "With Fusion"
        case .effect, .welcome: ""
        }
    }

    var guideIndex: Int {
        switch self {
        case .restore: 0
        case .pet: 1
        case .fusion: 2
        case .effect, .welcome: 0
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .welcome, .restore: .dark
        case .effect, .pet, .fusion: .light
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
        case .effect:
            []
        }
    }
}

private struct LaunchBackgroundMedia: View {
    let imageName: String
    let videoName: String?

    var body: some View {
        ZStack {
            Image(imageName)
                .resizable()
                .scaledToFill()

            if let videoName {
                LoopingVideoView(resourceName: videoName)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
    }
}

private struct WelcomeMarketingOverlay: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 2) {
                    HStack(alignment: .center, spacing: 15) {
                        Image(systemName: "laurel.leading")
                            .font(.system(size: 43, weight: .medium))

                        VStack(spacing: 2) {
                            Text("2M+")
                                .font(.system(size: 39, weight: .heavy))

                            HStack(spacing: 3) {
                                ForEach(0..<5, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.02))
                                }
                            }
                        }

                        Image(systemName: "laurel.trailing")
                            .font(.system(size: 43, weight: .medium))
                    }

                    Text("Users Worldwide")
                        .font(.system(size: 16, weight: .regular))
                }
                .foregroundStyle(.white)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.637)

                VStack(spacing: 8) {
                    Text("Welcome to\nPhoto Revive")
                        .font(.system(size: 31, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .lineSpacing(1)

                    Text("Bring Your Favorite Moments to Life")
                        .font(.system(size: 18, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .foregroundStyle(.white)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.773)

                OnboardingContinueButton(action: onContinue)
                    .padding(.horizontal, 20)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.890)
            }
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
                    y: proxy.size.height * (page == .fusion ? 0.775 : 0.797)
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
