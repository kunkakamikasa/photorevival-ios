import SwiftUI

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var trackingAuthorization = TrackingAuthorizationManager()
    @StateObject private var featureConfigStore = FeatureConfigStore()
    @State private var completedOnboardingThisSession = false
    @State private var showInitialMembership = false
    @State private var isShowingStartupVideo = true

    private let arguments = ProcessInfo.processInfo.arguments

    private var shouldShowOnboarding: Bool {
        guard !completedOnboardingThisSession else { return false }
        if arguments.contains("-forceOnboarding") { return true }
        if arguments.contains("-skipOnboarding") { return false }
        return !hasCompletedOnboarding
    }

    var body: some View {
        ZStack {
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
                    startupPresentationsAllowed: trackingAuthorization.hasFinishedInitialRequest
                )
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $showInitialMembership) {
            MembershipPaywallView()
        }
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
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        withAnimation(.easeInOut(duration: 0.35)) {
            completedOnboardingThisSession = true
        }
        showInitialMembership = true
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
            LaunchBackgroundMedia(imageName: page.imageName, videoName: page.videoName)

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
    case welcome
    case restore
    case pet
    case fusion

    var imageName: String {
        switch self {
        case .welcome: "OnboardingWelcomeBackground"
        case .restore: "OnboardingRestoreBackground"
        case .pet: "OnboardingPetBackground"
        case .fusion: "OnboardingFusionBackground"
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
            imageName: "OnboardingEffectBackground",
            videoName: "OnboardingLaunchVideo"
        )
        .accessibilityLabel("Photo Revive startup animation")
        .preferredColorScheme(.light)
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

private struct WelcomeVideoContinueHitTarget: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            Button(action: onContinue) {
                Color.clear
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .frame(height: 58)
            .padding(.horizontal, 20)
            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.890)
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
