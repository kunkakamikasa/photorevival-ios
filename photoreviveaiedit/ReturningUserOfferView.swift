import SwiftUI

struct ReturningOfferEligibility {
    static func shouldPresent(
        isReturningSession: Bool,
        isSubscribed: Bool,
        arguments: [String]
    ) -> Bool {
        guard !isSubscribed else { return false }
        guard !arguments.contains("-disableReturningOffer") else { return false }

        if arguments.contains("-forceReturningOffer") {
            return true
        }

        // Existing UI tests use this argument to enter the app without mutating
        // onboarding state. Keep those routes focused unless the offer is forced.
        guard !arguments.contains("-skipOnboarding") else { return false }
        return isReturningSession
    }

    static func canPresent(
        lastPresentedDay: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        LimitedOfferEligibility.canPresent(
            lastPresentedDay: lastPresentedDay,
            now: now,
            calendar: calendar
        )
    }
}

enum ReturningOfferVariant: String, CaseIterable, Equatable, Identifiable {
    case familyExclusive
    case superPrize
    case limitedTime

    var id: String { rawValue }

    static func select(
        arguments: [String],
        limitedTimeAvailable: Bool,
        randomIndex: Int? = nil
    ) -> Self {
        if arguments.contains("-forceSuperPrizeReturningOffer") {
            return .superPrize
        }

        if arguments.contains("-forceFamilyExclusiveReturningOffer") {
            return .familyExclusive
        }

        if arguments.contains("-forceLimitedTimeReturningOffer"), limitedTimeAvailable {
            return .limitedTime
        }

        let candidates: [Self] = limitedTimeAvailable
            ? [.familyExclusive, .superPrize, .limitedTime]
            : [.familyExclusive, .superPrize]
        let index = randomIndex ?? Int.random(in: 0..<candidates.count)
        return candidates[index % candidates.count]
    }
}

struct ReturningUserOfferFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isSubscribed") private var isSubscribed = false

    @State private var screen: ReturningOfferScreen = .family
    @State private var isPurchasing = false
    @State private var purchaseAlert: ReturningOfferPurchaseAlert?

    private let designSize = CGSize(width: 430, height: 932)
    private let analyticsSource: String

    init(
        startsAtTrial: Bool = false,
        analyticsSource: String = "returning_offer"
    ) {
        self.analyticsSource = analyticsSource
        _screen = State(initialValue: startsAtTrial ? .trial : .family)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = AspectFillLayout(source: designSize, destination: proxy.size)

            ZStack {
                Image(screen.assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                controls(using: layout)

                if isPurchasing {
                    StoreLoadingIndicator()
                        .transition(.opacity)
                        .accessibilityLabel("Opening App Store purchase")
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.light)
        .onAppear {
            trackPaywallScreen()
        }
        .onChange(of: screen) { _, _ in
            trackPaywallScreen()
        }
        .alert(item: $purchaseAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func controls(using layout: AspectFillLayout) -> some View {
        switch screen {
        case .family:
            hotspot(
                label: "Close family offer",
                identifier: "returning-offer-close",
                center: CGPoint(x: 37, y: 65),
                size: CGSize(width: 58, height: 58),
                layout: layout,
                action: showTrial
            )

            hotspot(
                label: "Claim My Offer",
                identifier: "returning-offer-claim",
                center: CGPoint(x: 215, y: 839),
                size: CGSize(width: 382, height: 70),
                layout: layout
            ) {
                beginPurchase(.weekly, origin: .family)
            }

        case .retention:
            hotspot(
                label: "Continue with weekly offer",
                identifier: "returning-retention-continue",
                center: CGPoint(x: 215, y: 739),
                size: CGSize(width: 354, height: 72),
                layout: layout
            ) {
                beginPurchase(.weekly, origin: .retention)
            }

            hotspot(
                label: "Close discount offer",
                identifier: "returning-retention-close",
                center: CGPoint(x: 215, y: 825),
                size: CGSize(width: 62, height: 62),
                layout: layout,
                action: dismiss.callAsFunction
            )

        case .trial:
            hotspot(
                label: "Close free trial offer",
                identifier: "returning-trial-close",
                center: CGPoint(x: 34, y: 66),
                size: CGSize(width: 58, height: 58),
                layout: layout,
                action: dismiss.callAsFunction
            )

            hotspot(
                label: "Start My 3-Day Free Trial",
                identifier: "returning-trial-start",
                center: CGPoint(x: 215, y: 839),
                size: CGSize(width: 382, height: 70),
                layout: layout
            ) {
                beginPurchase(.annual, origin: .trial)
            }

        }
    }

    private func hotspot(
        label: String,
        identifier: String,
        center: CGPoint,
        size: CGSize,
        layout: AspectFillLayout,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: size.width * layout.scale, height: size.height * layout.scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(layout.point(center))
        .disabled(isPurchasing)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func showTrial() {
        withAnimation(.easeInOut(duration: 0.2)) {
            screen = .trial
        }
    }

    private func trackPaywallScreen() {
        AppAnalytics.paywallViewed(
            variant: screen.analyticsName,
            source: analyticsSource,
            productID: screen.productIdentifier.rawValue,
            promotion: promotionContext(for: screen)
        )
    }

    private func promotionContext(
        for screen: ReturningOfferScreen,
        billingPeriod: String? = nil
    ) -> AppAnalytics.PromotionContext {
        AppAnalytics.PromotionContext(
            promotionID: screen.analyticsName,
            promotionName: "returning_offer",
            creativeName: screen.analyticsName,
            creativeSlot: analyticsSource,
            offerVariant: screen.analyticsName,
            billingPeriod: billingPeriod
        )
    }

    private func beginPurchase(_ plan: ReturningOfferPlan, origin: ReturningOfferPurchaseOrigin) {
        guard !isPurchasing else { return }

        isPurchasing = true
        let promotion = promotionContext(
            for: screen,
            billingPeriod: plan.rawValue
        )

        Task {
            let outcome = await ReturningOfferPurchaseService.purchase(
                plan,
                promotion: promotion
            )
            isPurchasing = false

            switch outcome {
            case .purchased:
                isSubscribed = true
                dismiss()
            case .cancelled:
                finishCancelledPurchase(from: origin)
            case .pending:
                purchaseAlert = ReturningOfferPurchaseAlert(
                    title: "Purchase Pending",
                    message: "Your purchase is waiting for approval. Premium will unlock after Apple confirms it."
                )
            case .unavailable:
                purchaseAlert = ReturningOfferPurchaseAlert(
                    title: "Purchase Unavailable",
                    message: "This subscription is not currently available from the App Store."
                )
            case .failed(let message):
                purchaseAlert = ReturningOfferPurchaseAlert(
                    title: "Purchase Unavailable",
                    message: message
                )
            }
        }
    }

    private func finishCancelledPurchase(from origin: ReturningOfferPurchaseOrigin) {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch origin {
            case .family, .retention:
                screen = .retention
            case .trial:
                screen = .trial
            }
        }
    }
}

private enum ReturningOfferScreen: Equatable {
    case family
    case retention
    case trial

    var analyticsName: String {
        switch self {
        case .family: "returning_family"
        case .retention: "returning_retention"
        case .trial: "three_day_trial"
        }
    }

    var assetName: String {
        switch self {
        case .family:
            "ReturningOfferFamily"
        case .retention:
            "ReturningOfferRetention"
        case .trial:
            "ReturningOfferFreeTrial"
        }
    }

    var productIdentifier: SubscriptionProductID {
        switch self {
        case .family, .retention:
            .familyExclusiveWeekly
        case .trial:
            .threeDayFreeTrialYearly
        }
    }
}

private enum ReturningOfferPurchaseOrigin: String, Equatable {
    case family
    case retention
    case trial
}

private enum ReturningOfferPlan: String, Equatable {
    case weekly
    case annual

    var productIdentifier: SubscriptionProductID {
        switch self {
        case .weekly:
            .familyExclusiveWeekly
        case .annual:
            .threeDayFreeTrialYearly
        }
    }
}

private enum ReturningOfferPurchaseOutcome {
    case purchased
    case cancelled
    case pending
    case unavailable
    case failed(String)
}

private enum ReturningOfferPurchaseService {
    static func purchase(
        _ plan: ReturningOfferPlan,
        promotion: AppAnalytics.PromotionContext
    ) async -> ReturningOfferPurchaseOutcome {
        switch await SubscriptionPurchaseService.purchase(
            plan.productIdentifier,
            promotion: promotion
        ) {
        case .purchased:
            return .purchased
        case .cancelled:
            return .cancelled
        case .pending:
            return .pending
        case .unavailable:
            return .unavailable
        case .failed(let message):
            return .failed(message)
        }
    }
}

struct ReturningPromotionFlowView: View {
    let variant: ReturningOfferVariant
    @Environment(\.dismiss) private var dismiss
    @State private var showsTrial = false

    var body: some View {
        Group {
            if showsTrial {
                ReturningUserOfferFlowView(startsAtTrial: true)
            } else {
                switch variant {
                case .familyExclusive:
                    ReturningUserOfferFlowView()
                case .superPrize:
                    SuperPrizeOfferView(
                        onClose: showTrial,
                        onPurchased: { dismiss() }
                    )
                case .limitedTime:
                    LimitedTimeOfferPopup(
                        onClose: showTrial,
                        onPurchased: { dismiss() },
                        analyticsSource: "returning_offer"
                    )
                }
            }
        }
    }

    private func showTrial() {
        withAnimation(.easeInOut(duration: 0.22)) {
            showsTrial = true
        }
    }
}

private struct ReturningOfferPurchaseAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct AspectFillLayout {
    let scale: CGFloat
    let origin: CGPoint

    init(source: CGSize, destination: CGSize) {
        scale = max(destination.width / source.width, destination.height / source.height)
        let renderedSize = CGSize(width: source.width * scale, height: source.height * scale)
        origin = CGPoint(
            x: (destination.width - renderedSize.width) / 2,
            y: (destination.height - renderedSize.height) / 2
        )
    }

    func point(_ sourcePoint: CGPoint) -> CGPoint {
        CGPoint(
            x: origin.x + sourcePoint.x * scale,
            y: origin.y + sourcePoint.y * scale
        )
    }
}

private struct StoreLoadingIndicator: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .tint(.white)
            .frame(width: 110, height: 110)
            .background(Color.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    ReturningUserOfferFlowView()
}
