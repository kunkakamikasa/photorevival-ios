import SwiftUI

enum PaywallFollowUpOffer: String, Identifiable, Equatable {
    case limitedTime
    case threeDayTrial

    var id: String { rawValue }

    static func select(
        limitedTimeAvailable: Bool,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        randomValue: Bool = Bool.random()
    ) -> Self {
        if arguments.contains("-forceThreeDayTrialOffer") {
            return .threeDayTrial
        }
        if arguments.contains("-forceLimitedOffer"), limitedTimeAvailable {
            return .limitedTime
        }
        return limitedTimeAvailable && randomValue ? .limitedTime : .threeDayTrial
    }
}

struct PaywallOfferFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isSubscribed") private var isSubscribed = false
    @AppStorage("limitedOfferLastPresentedDay") private var limitedOfferLastPresentedDay = 0.0
    @State private var followUpOffer: PaywallFollowUpOffer?
    private let analyticsSource: String
    private let upgradingFromProductID: String?

    init(
        analyticsSource: String = "membership_entry",
        upgradingFromProductID: String? = nil
    ) {
        self.analyticsSource = analyticsSource
        self.upgradingFromProductID = upgradingFromProductID
    }

    var body: some View {
        Group {
            if let followUpOffer {
                PaywallFollowUpOfferContent(
                    offer: followUpOffer,
                    analyticsSource: "membership_follow_up",
                    onFinish: { dismiss() }
                )
            } else {
                MembershipPaywallView(
                    isLoggedIn: upgradingFromProductID == nil ? nil : true,
                    analyticsSource: analyticsSource,
                    upgradingFromProductID: upgradingFromProductID,
                    onClose: presentFollowUpOffer
                )
            }
        }
    }

    private func presentFollowUpOffer() {
        guard !isSubscribed else {
            dismiss()
            return
        }

        if ProcessInfo.processInfo.arguments.contains("-resetLimitedOfferEligibility") {
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
        withAnimation(.easeInOut(duration: 0.22)) {
            followUpOffer = offer
        }
    }
}

struct PaywallFollowUpOfferView: View {
    let offer: PaywallFollowUpOffer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaywallFollowUpOfferContent(
            offer: offer,
            analyticsSource: "follow_up_offer",
            onFinish: { dismiss() }
        )
    }
}

private struct PaywallFollowUpOfferContent: View {
    let offer: PaywallFollowUpOffer
    let analyticsSource: String
    let onFinish: () -> Void

    @ViewBuilder
    var body: some View {
        switch offer {
        case .limitedTime:
            LimitedTimeOfferPopup(
                onClose: onFinish,
                onPurchased: onFinish,
                analyticsSource: analyticsSource
            )
        case .threeDayTrial:
            ReturningUserOfferFlowView(
                startsAtTrial: true,
                analyticsSource: analyticsSource
            )
        }
    }
}

struct SuperPrizeOfferView: View {
    let onClose: () -> Void
    let onPurchased: () -> Void
    @AppStorage("isSubscribed") private var isSubscribed = false
    @State private var isPurchasing = false
    @State private var purchaseAlert: SubscriptionPurchaseAlert?

    private let promotionContext = AppAnalytics.PromotionContext(
        promotionID: "super_prize",
        promotionName: "returning_offer",
        creativeName: "super_prize_ticket",
        creativeSlot: "returning_offer",
        offerVariant: "super_prize",
        billingPeriod: "weekly"
    )

    init(
        onClose: @escaping () -> Void,
        onPurchased: (() -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onPurchased = onPurchased ?? onClose
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CelebrationFragments()
                .opacity(0.8)
                .allowsHitTesting(false)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Text("SUPER PRIZE")
                            .font(.system(size: 42, weight: .heavy))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                            .padding(.top, 76)

                        Text("Returning Users Only")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .frame(height: 40)
                            .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1))
                            .padding(.top, 16)

                        SuperPrizeTicket()
                            .frame(maxWidth: 330)
                            .frame(height: min(390, proxy.size.height * 0.43))
                            .padding(.top, 24)

                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("Only")
                                    .font(.title2.bold())
                                Text("$1.14")
                                    .font(.system(size: 48, weight: .heavy))
                                    .foregroundStyle(.yellow)
                                Text("/Day")
                                    .font(.title2.bold())
                            }
                            Text("total $7.99/first week")
                                .font(.headline)
                            Text("Then $9.99/week")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.52))
                        }
                        .foregroundStyle(.white)
                        .padding(.top, 23)

                        Spacer(minLength: 28)

                        Button {
                            beginPurchase()
                        } label: {
                            HStack {
                                Spacer()
                                Text(isPurchasing ? "Connecting..." : "Continue")
                                    .font(.title3.bold())
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.title3.bold())
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .frame(height: 60)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 1, green: 0.53, blue: 0.08), AppPalette.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                        .buttonStyle(TemplatePressStyle())
                        .disabled(isPurchasing)
                        .accessibilityIdentifier("super-prize-continue")

                        Label("100% Refund Guarantee   Secured By Apple", systemImage: "apple.logo")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.top, 10)
                            .padding(.bottom, 16)
                    }
                    .frame(minHeight: proxy.size.height)
                    .padding(.horizontal, 22)
                }
                .scrollIndicators(.hidden)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title2.weight(.light))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close super prize")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 20)
            .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("super-prize-screen")
        .onAppear {
            AppAnalytics.paywallViewed(
                variant: "super_prize",
                source: "returning_offer",
                productID: SubscriptionProductID.superPrizeWeekly.rawValue,
                promotion: promotionContext
            )
        }
        .alert(item: $purchaseAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func beginPurchase() {
        guard !isPurchasing else { return }

        isPurchasing = true
        Task {
            let outcome = await SubscriptionPurchaseService.purchase(
                .superPrizeWeekly,
                promotion: promotionContext
            )
            isPurchasing = false

            switch outcome {
            case .purchased:
                isSubscribed = true
                onPurchased()
            case .cancelled:
                break
            case .pending:
                purchaseAlert = SubscriptionPurchaseAlert(
                    title: "Purchase Pending",
                    message: "Your purchase is waiting for approval. Premium will unlock after Apple confirms it."
                )
            case .unavailable:
                purchaseAlert = SubscriptionPurchaseAlert(
                    title: "Product Unavailable",
                    message: "The App Store product \(SubscriptionProductID.superPrizeWeekly.rawValue) is not available for this account."
                )
            case .failed(let message):
                purchaseAlert = SubscriptionPurchaseAlert(
                    title: "Purchase Unavailable",
                    message: message
                )
            }
        }
    }
}

private struct SuperPrizeTicket: View {
    var body: some View {
        ZStack {
            VoucherShape(notchRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.79, blue: 0.02), Color(red: 1, green: 0.37, blue: 0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.84))
                    .frame(height: 34)
                    .padding(.horizontal, 23)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.65), lineWidth: 9)
                            .padding(.horizontal, 13)
                    )
                    .offset(y: -9)

                Rectangle()
                    .fill(.clear)
                    .frame(height: 28)
                    .overlay {
                        Rectangle()
                            .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [7, 7]))
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                    }

                HStack(alignment: .center, spacing: 4) {
                    Text("20")
                        .font(.system(size: 108, weight: .heavy))
                    VStack(alignment: .leading, spacing: -8) {
                        Text("%")
                            .font(.system(size: 54, weight: .heavy))
                        Text("OFF")
                            .font(.system(size: 40, weight: .heavy))
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.20), radius: 2, y: 3)
                .minimumScaleFactor(0.72)

                Text("Limited Time Only")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .frame(height: 42)
                    .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                    .padding(.top, 4)

                Spacer(minLength: 12)
            }
            .padding(.vertical, 10)
        }
        .shadow(color: .orange.opacity(0.28), radius: 18, y: 8)
    }
}

struct LimitedTimeOfferPopup: View {
    let onClose: () -> Void
    let onPurchased: () -> Void
    private let analyticsSource: String
    @AppStorage("isSubscribed") private var isSubscribed = false
    @State private var remainingHundredths = 60 * 100 - 1
    @State private var isPurchasing = false
    @State private var purchaseAlert: SubscriptionPurchaseAlert?

    init(
        onClose: @escaping () -> Void,
        onPurchased: (() -> Void)? = nil,
        analyticsSource: String = "follow_up_offer"
    ) {
        self.onClose = onClose
        self.onPurchased = onPurchased ?? onClose
        self.analyticsSource = analyticsSource
    }

    private var promotionContext: AppAnalytics.PromotionContext {
        AppAnalytics.PromotionContext(
            promotionID: "limited_time_offer",
            promotionName: "limited_time",
            creativeName: "limited_time_popup",
            creativeSlot: analyticsSource,
            offerVariant: "limited_time",
            billingPeriod: "annual"
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [LimitedOfferPalette.backdropTop, LimitedOfferPalette.backdropBottom],
                startPoint: .top,
                endPoint: .bottom
            )
                .opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        offerCard
                            .frame(maxWidth: min(390, proxy.size.width - 32))

                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .foregroundStyle(LimitedOfferPalette.onAccentText)
                                .frame(width: 46, height: 46)
                                .background(LimitedOfferPalette.closeButton, in: Circle())
                                .overlay(
                                    Circle().stroke(
                                        LimitedOfferPalette.orange.opacity(0.70),
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close limited offer")
                    }
                    .frame(minHeight: proxy.size.height)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityIdentifier("limited-time-offer-popup")
        .onAppear {
            AppAnalytics.paywallViewed(
                variant: "limited_time",
                source: analyticsSource,
                productID: SubscriptionProductID.limitedTimeOfferYearly.rawValue,
                promotion: promotionContext
            )
        }
        .task {
            while remainingHundredths > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000)
                if !Task.isCancelled { remainingHundredths -= 1 }
            }
        }
        .alert(item: $purchaseAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var offerCard: some View {
        VStack(spacing: 18) {
            Text("Limited Time Offer!")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(
                    LinearGradient(
                        colors: [LimitedOfferPalette.coral, LimitedOfferPalette.orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            VStack(spacing: 10) {
                Text("◆ PRO")
                    .font(.headline.bold())
                    .foregroundStyle(LimitedOfferPalette.onAccentText)
                    .padding(.horizontal, 22)
                    .frame(height: 36)
                    .background(
                        LinearGradient(
                            colors: [LimitedOfferPalette.coral, LimitedOfferPalette.orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .offset(y: -20)

                VStack(alignment: .leading, spacing: 7) {
                    benefitColumn(["Evolving & Customizable Styles"])

                    HStack(alignment: .top, spacing: 18) {
                        benefitColumn(["Priority", "No Watermark", "30% OFF Credit"])
                        benefitColumn(["Ad-Free", "260 per week"])
                    }
                }
                .padding(.top, -15)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .background(LimitedOfferPalette.benefitSurface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(LimitedOfferPalette.warmStroke.opacity(0.55), lineWidth: 1)
            )

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("50%")
                    .font(.system(size: 72, weight: .heavy))
                Text("OFF")
                    .font(.system(size: 32, weight: .heavy))
            }
            .foregroundStyle(
                LinearGradient(
                    colors: [LimitedOfferPalette.coral, LimitedOfferPalette.orange],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$24.99")
                        .font(.system(size: 35, weight: .bold))
                    Text("first year")
                        .font(.headline)
                }
                .foregroundStyle(LimitedOfferPalette.primaryText)
                Text("Then $49.99/year")
                    .font(.title3)
                    .foregroundStyle(LimitedOfferPalette.secondaryText)
            }

            CountdownView(hundredths: remainingHundredths)

            Button {
                beginPurchase()
            } label: {
                Text(isPurchasing ? "Connecting..." : "Try Now")
                    .font(.title2.bold())
                    .foregroundStyle(LimitedOfferPalette.onAccentText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        LinearGradient(
                            colors: [LimitedOfferPalette.buttonStart, LimitedOfferPalette.buttonEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(.white.opacity(0.20), lineWidth: 1))
            }
            .buttonStyle(TemplatePressStyle())
            .disabled(isPurchasing)
            .accessibilityIdentifier("limited-offer-try-now")
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [LimitedOfferPalette.cardTop, LimitedOfferPalette.cardBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(LimitedOfferPalette.warmStroke.opacity(0.44), lineWidth: 1)
        )
        .shadow(color: LimitedOfferPalette.coral.opacity(0.18), radius: 24, y: 10)
    }

    private func beginPurchase() {
        guard !isPurchasing else { return }

        isPurchasing = true
        Task {
            let outcome = await SubscriptionPurchaseService.purchase(
                .limitedTimeOfferYearly,
                promotion: promotionContext
            )
            isPurchasing = false

            switch outcome {
            case .purchased:
                isSubscribed = true
                onPurchased()
            case .cancelled:
                break
            case .pending:
                purchaseAlert = SubscriptionPurchaseAlert(
                    title: "Purchase Pending",
                    message: "Your purchase is waiting for approval. Premium will unlock after Apple confirms it."
                )
            case .unavailable:
                purchaseAlert = SubscriptionPurchaseAlert(
                    title: "Product Unavailable",
                    message: "The App Store product \(SubscriptionProductID.limitedTimeOfferYearly.rawValue) is not available for this account."
                )
            case .failed(let message):
                purchaseAlert = SubscriptionPurchaseAlert(
                    title: "Purchase Unavailable",
                    message: message
                )
            }
        }
    }

    private func benefitColumn(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(items, id: \.self) { item in
                Text("- \(item)")
                    .font(.subheadline)
                    .foregroundStyle(LimitedOfferPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum LimitedOfferPalette {
    static let backdropTop = Color(red: 0.13, green: 0.08, blue: 0.04)
    static let backdropBottom = Color(red: 0.04, green: 0.025, blue: 0.015)
    static let cardTop = AppPalette.backgroundTop
    static let cardBottom = AppPalette.surfaceCenter
    static let benefitSurface = Color.white.opacity(0.76)
    static let closeButton = AppPalette.ink.opacity(0.88)
    static let primaryText = AppPalette.ink
    static let secondaryText = AppPalette.brownInk.opacity(0.72)
    static let onAccentText = Color.white
    static let coral = AppPalette.accent
    static let orange = AppPalette.orange
    static let warmStroke = AppPalette.surfaceEdge
    static let buttonStart = AppPalette.ink
    static let buttonEnd = AppPalette.brownInk
}

private struct CountdownView: View {
    let hundredths: Int

    private var parts: [String] {
        let minutes = hundredths / 6_000
        let seconds = (hundredths / 100) % 60
        let centiseconds = hundredths % 100
        return [
            String(format: "%02d", minutes),
            String(format: "%02d", seconds),
            String(format: "%02d", centiseconds)
        ]
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(LimitedOfferPalette.onAccentText)
                    .frame(width: 62, height: 52)
                    .background(
                        LinearGradient(
                            colors: [LimitedOfferPalette.coral, LimitedOfferPalette.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                if index < parts.count - 1 {
                    Text(":")
                        .font(.title2.bold())
                        .foregroundStyle(LimitedOfferPalette.coral)
                }
            }
        }
        .accessibilityLabel("Offer countdown")
    }
}

struct SummerSalePaywallView: View {
    let offer: CMSCouponOffer
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isSubscribed") private var isSubscribed = false
    @State private var selectedPlan: CouponPlanKind = .annual
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseAlert: SubscriptionPurchaseAlert?

    private var promotionContext: AppAnalytics.PromotionContext {
        AppAnalytics.PromotionContext(
            promotionID: offer.id,
            promotionName: "summer_sale",
            creativeName: "summer_discount_sign",
            creativeSlot: offer.placement,
            offerVariant: "summer_sale_\(selectedPlan.rawValue)",
            billingPeriod: selectedPlan.rawValue
        )
    }

    var body: some View {
        ZStack {
            SummerBeachBackdrop()

            GeometryReader { proxy in
                let compact = proxy.size.height < 820
                let horizontalPadding: CGFloat = compact ? 18 : 26
                let signHeight = min(max(proxy.size.height * 0.255, 192), 248)
                let cardHeight = min(max(proxy.size.height * 0.215, 176), 218)

                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 27, weight: .light))
                                .foregroundStyle(Color.black.opacity(0.88))
                                .frame(width: 48, height: 48)
                                .background(.white.opacity(0.82), in: Circle())
                        }
                        .buttonStyle(TemplatePressStyle())
                        .accessibilityLabel("Close summer offer")

                        Spacer()

                        Button(action: restorePurchases) {
                            Text(isRestoring ? "Restoring..." : "Restore")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(Color(red: 0.55, green: 0.31, blue: 0.10))
                                .padding(.horizontal, 22)
                                .frame(height: 48)
                                .background(.white.opacity(0.84), in: Capsule())
                        }
                        .buttonStyle(TemplatePressStyle())
                        .disabled(isRestoring || isPurchasing)
                        .accessibilityIdentifier("summer-offer-restore")
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, compact ? 4 : 8)

                    SummerPromotionHeadline(compact: compact)
                        .padding(.top, compact ? 3 : 7)

                    HStack(spacing: 8) {
                        SummerSparkleRule()
                        Text("You've got a Special gift!")
                            .font(.system(size: compact ? 16 : 18, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.84))
                            .minimumScaleFactor(0.78)
                            .lineLimit(1)
                        SummerSparkleRule()
                            .scaleEffect(x: -1, y: 1)
                    }
                    .padding(.horizontal, horizontalPadding + 12)
                    .padding(.top, compact ? 0 : 3)

                    SummerDiscountSign()
                        .frame(height: signHeight)
                        .padding(.horizontal, compact ? 7 : 11)
                        .padding(.top, compact ? 1 : 5)

                    HStack(spacing: compact ? 12 : 16) {
                        SummerPlanCard(
                            kind: .weekly,
                            plan: offer.weeklyPlan,
                            selectedPlan: $selectedPlan
                        )
                        SummerPlanCard(
                            kind: .annual,
                            plan: offer.annualPlan,
                            selectedPlan: $selectedPlan
                        )
                    }
                    .frame(height: cardHeight)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, compact ? 5 : 9)

                    Spacer(minLength: compact ? 10 : 18)

                    Button(action: beginPurchase) {
                        HStack {
                            Spacer()
                            Text(isPurchasing ? "Connecting..." : "Continue")
                                .font(.system(size: 22, weight: .bold))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 22, weight: .regular))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .frame(height: compact ? 56 : 62)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.57, blue: 0), Color(red: 1, green: 0.20, blue: 0.16)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: Color.orange.opacity(0.14), radius: 8, y: 5)
                    }
                    .buttonStyle(TemplatePressStyle())
                    .disabled(isPurchasing || isRestoring)
                    .accessibilityIdentifier("summer-offer-continue")
                    .accessibilityValue(offer.plan(for: selectedPlan).productID)
                    .padding(.horizontal, horizontalPadding + 2)

                    Label("Cancel anytime", systemImage: "checkmark.shield")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.68))
                        .padding(.top, compact ? 7 : 10)
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom, 8))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }

            if isPurchasing || isRestoring {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
                    .padding(18)
                    .background(.black.opacity(0.42), in: Circle())
            }
        }
        .preferredColorScheme(.light)
        .sensoryFeedback(.selection, trigger: selectedPlan)
        .accessibilityIdentifier("summer-sale-screen")
        .onAppear {
            AppAnalytics.paywallViewed(
                variant: "summer_sale",
                source: offer.placement,
                productID: offer.plan(for: selectedPlan).productID,
                promotion: promotionContext
            )
        }
        .alert(item: $purchaseAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func beginPurchase() {
        guard !isPurchasing else { return }

        let productID = offer.plan(for: selectedPlan).productID
        isPurchasing = true

        Task {
            let outcome = await SubscriptionPurchaseService.purchase(
                productID,
                promotion: promotionContext
            )
            isPurchasing = false

            switch outcome {
            case .purchased:
                isSubscribed = true
                dismiss()
            case .cancelled:
                break
            case .pending:
                purchaseAlert = SubscriptionPurchaseAlert(
                    title: "Purchase Pending",
                    message: "Your purchase is waiting for approval. Premium will unlock after Apple confirms it."
                )
            case .unavailable:
                purchaseAlert = SubscriptionPurchaseAlert(
                    title: "Product Unavailable",
                    message: "The App Store product \(productID) is not available for this account."
                )
            case .failed(let message):
                purchaseAlert = SubscriptionPurchaseAlert(
                    title: "Purchase Unavailable",
                    message: message
                )
            }
        }
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true

        Task {
            let outcome = await SubscriptionPurchaseService.restore()
            isRestoring = false

            switch outcome {
            case .purchased:
                isSubscribed = true
                dismiss()
            case .unavailable:
                purchaseAlert = SubscriptionPurchaseAlert(
                    title: "No Purchases Found",
                    message: "No active subscription was found for this Apple ID."
                )
            case .failed(let message):
                purchaseAlert = SubscriptionPurchaseAlert(
                    title: "Restore Unavailable",
                    message: message
                )
            case .cancelled, .pending:
                break
            }
        }
    }
}

private struct SummerPromotionHeadline: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? -9 : -7) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Color(red: 1, green: 0.52, blue: 0.02))
                    .frame(width: compact ? 24 : 31, height: 2)
                Text("Congratulations")
                    .font(.custom("SnellRoundhand-Bold", size: compact ? 42 : 49))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.73, blue: 0.02), Color(red: 1, green: 0.43, blue: 0.01)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Capsule()
                    .fill(Color(red: 1, green: 0.52, blue: 0.02))
                    .frame(width: compact ? 24 : 31, height: 2)
            }

            HStack(spacing: 5) {
                Capsule().frame(width: compact ? 42 : 58, height: 1.5)
                Image(systemName: "heart.fill")
                    .font(.system(size: compact ? 15 : 18))
                Capsule().frame(width: compact ? 42 : 58, height: 1.5)
            }
            .foregroundStyle(Color(red: 1, green: 0.48, blue: 0.04))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Congratulations")
    }
}

private struct SummerSparkleRule: View {
    var body: some View {
        HStack(spacing: 3) {
            Capsule().frame(width: 18, height: 1.5)
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(Color(red: 1, green: 0.58, blue: 0.02))
    }
}

private struct SummerPlanCard: View {
    let kind: CouponPlanKind
    let plan: CMSCouponPlan
    @Binding var selectedPlan: CouponPlanKind

    private var title: String { kind == .weekly ? "Weekly Plan" : "Annual Plan" }
    private var price: String { kind == .weekly ? "$9.99" : "$39.99" }
    private var period: String { kind == .weekly ? "/week" : "/year" }
    private var dailyPrice: String { kind == .weekly ? "$1.43" : "$0.11" }
    private var accent: Color {
        kind == .weekly
            ? Color(red: 0.20, green: 0.68, blue: 0.86)
            : Color(red: 1.00, green: 0.36, blue: 0.08)
    }
    private var bottomTint: Color {
        kind == .weekly
            ? Color(red: 0.75, green: 0.94, blue: 0.98)
            : Color(red: 1.00, green: 0.90, blue: 0.50)
    }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { selectedPlan = kind }
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.91))

                SummerWaveShape()
                    .fill(bottomTint.opacity(0.80))
                    .frame(height: 49)

                VStack(spacing: 0) {
                    Text(title)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.gray.opacity(0.86))

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(price)
                            .font(.system(size: kind == .annual ? 23 : 21, weight: .heavy))
                        Text(period)
                            .font(.system(size: kind == .annual ? 15 : 14, weight: .regular))
                    }
                    .foregroundStyle(AppPalette.ink)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .padding(.top, 15)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(dailyPrice)
                            .font(.system(size: 17, weight: .semibold))
                        Text("/day")
                            .font(.system(size: 14, weight: .regular))
                    }
                    .foregroundStyle(AppPalette.ink)
                    .padding(.top, 12)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Image("RewardsCreditToken")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("400 per week")
                    }
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(red: 0.38, green: 0.29, blue: 0.20))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                }
                .padding(.top, 28)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(accent.opacity(selectedPlan == kind ? 1 : 0.68), lineWidth: selectedPlan == kind ? 3.5 : 1.5)
            )
            .shadow(color: selectedPlan == kind ? accent.opacity(0.18) : .clear, radius: 8, y: 4)
            .overlay(alignment: .top) {
                if kind == .annual {
                    Text("Most popular")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.31, blue: 0.22), Color(red: 1, green: 0.18, blue: 0.14)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Capsule()
                        )
                        .offset(y: -17)
                } else {
                    Image("SummerPromoShell")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .offset(y: -23)
                }
            }
            .overlay(alignment: .topTrailing) {
                if kind == .annual {
                    Image("SummerPromoStarfish")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 51, height: 51)
                        .offset(x: 8, y: -22)
                }
            }
        }
        .buttonStyle(TemplatePressStyle())
        .accessibilityLabel(title)
        .accessibilityValue(selectedPlan == kind ? "Selected" : "Not selected")
    }
}

private struct SummerDiscountSign: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("SummerPromoSign")
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                VStack(spacing: proxy.size.height * 0.025) {
                    Text("65% OFF")
                        .font(.system(size: min(proxy.size.width * 0.145, 61), weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1.00, green: 0.65, blue: 0.02), Color(red: 1.00, green: 0.20, blue: 0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .white.opacity(0.78), radius: 0, y: 2)
                        .minimumScaleFactor(0.76)
                        .lineLimit(1)

                    Text("LIMITED TIME ONLY")
                        .font(.system(size: min(proxy.size.width * 0.038, 16), weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .frame(height: min(proxy.size.height * 0.16, 35))
                        .background(Color(red: 0.04, green: 0.55, blue: 0.70), in: SummerRibbonShape())
                }
                .offset(y: proxy.size.height * 0.045)
                .padding(.horizontal, proxy.size.width * 0.21)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("65 percent off, limited time only")
    }
}

private struct SummerRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notch = min(rect.height * 0.28, rect.width * 0.08)
        var path = Path()
        path.move(to: CGPoint(x: notch, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - notch, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.maxY))
        path.addLine(to: CGPoint(x: notch, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct SummerWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.25))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.20),
            control1: CGPoint(x: rect.width * 0.17, y: -rect.height * 0.05),
            control2: CGPoint(x: rect.width * 0.33, y: rect.height * 0.48)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.13),
            control1: CGPoint(x: rect.width * 0.67, y: -rect.height * 0.03),
            control2: CGPoint(x: rect.width * 0.82, y: rect.height * 0.42)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SummerBeachBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            Image("SummerPromoBackgroundV2")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }
}

private struct VoucherShape: Shape {
    var notchRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 14
        let middleY = rect.midY
        var path = Path()

        path.move(to: CGPoint(x: cornerRadius, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: cornerRadius), control: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: middleY - notchRadius))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: middleY + notchRadius),
            control1: CGPoint(x: rect.maxX - notchRadius * 1.25, y: middleY - notchRadius),
            control2: CGPoint(x: rect.maxX - notchRadius * 1.25, y: middleY + notchRadius)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: cornerRadius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - cornerRadius), control: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: middleY + notchRadius))
        path.addCurve(
            to: CGPoint(x: 0, y: middleY - notchRadius),
            control1: CGPoint(x: notchRadius * 1.25, y: middleY + notchRadius),
            control2: CGPoint(x: notchRadius * 1.25, y: middleY - notchRadius)
        )
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        path.addQuadCurve(to: CGPoint(x: cornerRadius, y: 0), control: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct CelebrationFragments: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                fragment(.yellow, x: 0.08, y: 0.31, rotation: -36, in: proxy.size)
                fragment(.blue, x: 0.13, y: 0.52, rotation: 28, in: proxy.size)
                fragment(.pink, x: 0.88, y: 0.44, rotation: -18, in: proxy.size)
                fragment(.mint, x: 0.91, y: 0.30, rotation: 76, in: proxy.size)
                fragment(.orange, x: 0.88, y: 0.69, rotation: 42, in: proxy.size)
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.cyan, .pink)
                    .position(x: proxy.size.width * 0.88, y: proxy.size.height * 0.22)
            }
        }
    }

    private func fragment(
        _ color: Color,
        x: CGFloat,
        y: CGFloat,
        rotation: Double,
        in size: CGSize
    ) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 48, height: 16)
            .rotationEffect(.degrees(rotation))
            .position(x: size.width * x, y: size.height * y)
            .blur(radius: 1)
    }
}
