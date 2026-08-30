import SwiftUI
import UIKit

enum SubscriberScratchCampaign {
    static let version = 1
    static let freeCredits = 100
    static let freeCreditLifetime: TimeInterval = 2 * 60 * 60
    static let rewardTaskCode = "subscriber_return_scratch_100"
}

struct SubscriberScratchEligibility {
    static func shouldPresent(
        isReturningSession: Bool,
        isSubscribed: Bool,
        completedCampaignVersion: Int,
        arguments: [String]
    ) -> Bool {
        guard !arguments.contains("-disableSubscriberScratchOffer") else {
            return false
        }

        if arguments.contains("-forceSubscriberScratchOffer") {
            return true
        }

        // Preview and UI-test routes stay deterministic unless this flow is
        // explicitly forced.
        guard !arguments.contains("-skipOnboarding") else { return false }
        guard isReturningSession, isSubscribed else { return false }
        return completedCampaignVersion < SubscriberScratchCampaign.version
    }
}

struct SubscriberScratchOfferView: View {
    @ObservedObject private var accountStore: AppAccountStore
    @Environment(\.dismiss) private var dismiss

    let onRewardClaimed: () -> Void
    var claimOverride: (() async throws -> Void)?
    var purchaseOverride: ((CreditPack) async throws -> Void)?

    @State private var stage: SubscriberScratchStage = .freeScratch
    @State private var isWorking = false
    @State private var alert: SubscriberScratchAlert?
    @State private var showsCreditToast = false
    @State private var celebrationID = 0
    @State private var purchaseTask: Task<Void, Never>?
    @State private var legalDocument: LegalDocument?
    @StateObject private var priceStore = StoreProductPriceStore.shared

    init(
        accountStore: AppAccountStore? = nil,
        onRewardClaimed: @escaping () -> Void,
        claimOverride: (() async throws -> Void)? = nil,
        purchaseOverride: ((CreditPack) async throws -> Void)? = nil
    ) {
        self.accountStore = accountStore ?? .shared
        self.onRewardClaimed = onRewardClaimed
        self.claimOverride = claimOverride
        self.purchaseOverride = purchaseOverride
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                SubscriberScratchBackground()

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        header

                        scratchCard
                            .frame(height: min(292, proxy.size.width * 0.71))
                            .padding(.horizontal, 20)
                            .padding(.top, 24)

                        actionArea
                            .padding(.top, 24)

                        Spacer(minLength: max(proxy.safeAreaInsets.bottom, 18))
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(stage == .freeScratch || stage == .bonusScratch)

                if celebrationID > 0 {
                    SubscriberScratchCelebration(key: celebrationID)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if showsCreditToast {
                    Text("\(SubscriberScratchCampaign.freeCredits) credits added")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 45)
                        .background(.black.opacity(0.82), in: Capsule())
                        .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, proxy.safeAreaInsets.top + 12)
                }

                if isWorking {
                    StorePurchaseLoadingOverlay(accessibilityLabel: "Processing reward")
                }
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("subscriber-scratch-flow")
        .alert(item: $alert) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .fullScreenCover(item: $legalDocument) { document in
            InAppBrowserView(url: document.url)
                .ignoresSafeArea()
        }
        .onChange(of: stage) { _, newStage in
            guard newStage == .offerRevealed else { return }
            AppAnalytics.paywallViewed(
                variant: "subscriber_scratch_1600",
                source: "subscriber_return",
                productID: CreditProductCatalog.subscriberReturnOffer.productID,
                promotion: subscriberPromotion
            )
        }
        .onDisappear {
            purchaseTask?.cancel()
        }
        .task {
            await priceStore.load(
                productIDs: [CreditProductCatalog.subscriberReturnOffer.productID].compactMap { $0 }
            )
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 9) {
                Text(stage.title)
                    .font(.system(size: 35, weight: .black, design: .rounded))
                    .foregroundStyle(SubscriberScratchPalette.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .lineLimit(2)

                Text(stage.subtitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SubscriberScratchPalette.ink.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 42)

            Image(systemName: "sparkles")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(SubscriberScratchPalette.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .offset(y: 19)

            Image(systemName: "sparkle")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(SubscriberScratchPalette.orange)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
                .offset(y: -30)
        }
        .padding(.top, 28)
    }

    @ViewBuilder
    private var scratchCard: some View {
        switch stage {
        case .freeScratch:
            SmoothScratchCard(
                style: .gold,
                accessibilityIdentifier: "subscriber-scratch-card-free",
                onReveal: revealFreeReward
            ) {
                SubscriberFreeRewardCard()
            }
            .transition(.opacity)

        case .freeRevealed, .claimingFree:
            SubscriberFreeRewardCard()
                .overlay {
                    if stage == .freeRevealed {
                        SubscriberCardGlow()
                            .allowsHitTesting(false)
                    }
                }

        case .bonusScratch:
            SmoothScratchCard(
                style: .coral,
                accessibilityIdentifier: "subscriber-scratch-card-1600",
                onReveal: revealPaidOffer
            ) {
                SubscriberPaidRewardCard()
            }
            .transition(.opacity)

        case .offerRevealed:
            SubscriberPaidRewardCard()
                .overlay {
                    SubscriberCardGlow()
                        .allowsHitTesting(false)
                }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch stage {
        case .freeScratch:
            Label("Two surprises are waiting for you", systemImage: "gift.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SubscriberScratchPalette.ink.opacity(0.64))
                .accessibilityIdentifier("subscriber-scratch-free-hint")

        case .freeRevealed, .claimingFree:
            VStack(spacing: 12) {
                Text("They expire 2 hours after you claim them.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SubscriberScratchPalette.ink.opacity(0.66))

                Button(action: claimFreeReward) {
                    SubscriberScratchPrimaryButton(
                        title: stage == .claimingFree ? "Adding credits..." : "Add 100 credits",
                        systemImage: "gift.fill"
                    )
                }
                .buttonStyle(TemplatePressStyle())
                .disabled(isWorking)
                .accessibilityIdentifier("subscriber-scratch-claim-free")
                .padding(.horizontal, 20)
            }

        case .bonusScratch:
            Label("100 credits added • valid for 2 hours", systemImage: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SubscriberScratchPalette.ink.opacity(0.64))
                .accessibilityIdentifier("subscriber-scratch-paid-hint")

        case .offerRevealed:
            VStack(spacing: 16) {
                Text(priceStore.displayPrice(
                    for: CreditProductCatalog.subscriberReturnOffer.productID,
                    fallback: CreditProductCatalog.subscriberReturnOffer.displayPrice
                ))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(SubscriberScratchPalette.ink)

                Button(action: beginPurchase) {
                    SubscriberScratchPrimaryButton(
                        title: isWorking ? "Connecting..." : "Get 1,600 credits",
                        systemImage: "checkmark.shield.fill"
                    )
                }
                .buttonStyle(TemplatePressStyle())
                .disabled(isWorking)
                .accessibilityIdentifier("subscriber-scratch-purchase")
                .padding(.horizontal, 20)

                HStack(spacing: 13) {
                    Label("Pay once", systemImage: "creditcard.fill")
                    Divider()
                        .frame(height: 18)
                    Label("Never expires", systemImage: "infinity")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SubscriberScratchPalette.ink.opacity(0.58))

                LegalLinksView(onOpen: { legalDocument = $0 })
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SubscriberScratchPalette.ink.opacity(0.62))

                Button {
                    purchaseTask?.cancel()
                    isWorking = false
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SubscriberScratchPalette.ink.opacity(0.62))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.64), in: Circle())
                        .overlay(Circle().stroke(SubscriberScratchPalette.ink.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close subscriber credit offer")
                .accessibilityIdentifier("subscriber-scratch-close")
            }
        }
    }

    private var subscriberPromotion: AppAnalytics.PromotionContext {
        CreditPurchasePromotion.surprise1600
    }

    private func revealFreeReward() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            stage = .freeRevealed
            celebrationID += 1
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func revealPaidOffer() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            stage = .offerRevealed
            celebrationID += 1
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func claimFreeReward() {
        guard !isWorking else { return }
        isWorking = true
        stage = .claimingFree

        Task {
            do {
                if let claimOverride {
                    try await claimOverride()
                } else {
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-simulateSubscriberScratchClaim") {
                        try await Task.sleep(for: .milliseconds(260))
                    } else {
                        _ = try await accountStore.claimSubscriberScratchReward()
                    }
#else
                    _ = try await accountStore.claimSubscriberScratchReward()
#endif
                }

                onRewardClaimed()
                isWorking = false
                withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                    showsCreditToast = true
                }
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(.easeInOut(duration: 0.28)) {
                    showsCreditToast = false
                    stage = .bonusScratch
                }
            } catch {
                isWorking = false
                stage = .freeRevealed
                alert = SubscriberScratchAlert(
                    title: "Unable to add credits",
                    message: error.userFacingEnglishMessage()
                )
            }
        }
    }

    private func beginPurchase() {
        guard !isWorking else { return }
        let offer = CreditProductCatalog.subscriberReturnOffer
        guard let productID = offer.productID, !productID.isEmpty else {
            alert = SubscriberScratchAlert(
                title: "Product ID needed",
                message: "The 1,600-credit offer is ready. Add its consumable Product ID to CreditProductCatalog to connect checkout."
            )
            return
        }

        isWorking = true
        purchaseTask = Task {
            if let purchaseOverride {
                do {
                    AppAnalytics.promotionSelected(subscriberPromotion, productID: productID)
                    try await purchaseOverride(offer)
                    guard !Task.isCancelled else { return }
                    isWorking = false
                    dismiss()
                } catch {
                    guard !Task.isCancelled else { return }
                    isWorking = false
                    alert = SubscriberScratchAlert(
                        title: "Purchase unavailable",
                        message: error.userFacingEnglishMessage()
                    )
                }
                return
            }

            let outcome = await CreditPurchaseService.purchase(
                offer,
                promotion: subscriberPromotion
            )
            guard !Task.isCancelled else { return }
            isWorking = false
            switch outcome {
            case .purchased:
                dismiss()
            case .cancelled:
                break
            case .pending:
                alert = SubscriberScratchAlert(
                    title: "Purchase pending",
                    message: "Apple is still processing this purchase. Your credits will be added after confirmation."
                )
            case .unavailable:
                alert = SubscriberScratchAlert(
                    title: "Product unavailable",
                    message: "The 1,600-credit surprise is not currently available from the App Store."
                )
            case .failed(let message):
                alert = SubscriberScratchAlert(
                    title: "Purchase unavailable",
                    message: message
                )
            }
        }
    }
}

private enum SubscriberScratchStage: Equatable {
    case freeScratch
    case freeRevealed
    case claimingFree
    case bonusScratch
    case offerRevealed

    var title: String {
        switch self {
        case .freeScratch:
            "Scratch your welcome gift"
        case .freeRevealed, .claimingFree:
            "100 credits unlocked!"
        case .bonusScratch:
            "One more surprise"
        case .offerRevealed:
            "Your bigger reward"
        }
    }

    var subtitle: String {
        switch self {
        case .freeScratch:
            "A thank-you gift for being a subscriber"
        case .freeRevealed, .claimingFree:
            "Your free credits are ready"
        case .bonusScratch:
            "Scratch to reveal a member-only credit pack"
        case .offerRevealed:
            "A one-time subscriber-exclusive offer"
        }
    }
}

private struct SubscriberScratchAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum SubscriberScratchPalette {
    static let ink = Color(red: 0.23, green: 0.12, blue: 0.035)
    static let gold = Color(red: 0.98, green: 0.68, blue: 0.10)
    static let orange = Color(red: 1.00, green: 0.39, blue: 0.10)
    static let cream = Color(red: 1.00, green: 0.97, blue: 0.85)
}

private struct SubscriberScratchBackground: View {
    var body: some View {
        ZStack {
            Color.white

            RadialGradient(
                colors: [Color.pink.opacity(0.19), .clear],
                center: UnitPoint(x: 0.05, y: 0.04),
                startRadius: 5,
                endRadius: 280
            )

            RadialGradient(
                colors: [Color(red: 1.00, green: 0.42, blue: 0.32).opacity(0.20), .clear],
                center: UnitPoint(x: 0.94, y: 0.58),
                startRadius: 15,
                endRadius: 310
            )

            RadialGradient(
                colors: [Color.yellow.opacity(0.19), .clear],
                center: UnitPoint(x: 0.12, y: 0.94),
                startRadius: 8,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
    }
}

private struct SubscriberFreeRewardCard: View {
    var body: some View {
        VStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(SubscriberScratchPalette.gold.opacity(0.15))
                    .frame(width: 82, height: 82)
                Image("RewardsCreditToken")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 68, height: 68)
            }

            Text("+100")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [SubscriberScratchPalette.orange, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("100 CREDITS FREE")
                .font(.system(size: 12, weight: .black))
                .tracking(2.0)
                .foregroundStyle(SubscriberScratchPalette.ink.opacity(0.62))

            VStack(spacing: 0) {
                Text("PHOTO REVIVAL CREDITS")
                Text("(VALID FOR 2 HOURS)")
            }
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(
                    LinearGradient(
                        colors: [SubscriberScratchPalette.gold, SubscriberScratchPalette.orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(SubscriberScratchPalette.gold.opacity(0.72), lineWidth: 3)
        )
        .shadow(color: SubscriberScratchPalette.gold.opacity(0.18), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("100 free welcome-back credits")
    }
}

private struct SubscriberPaidRewardCard: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("SUBSCRIBER EXCLUSIVE")
                .font(.system(size: 11, weight: .black))
                .tracking(1.1)
                .foregroundStyle(.white)
                .padding(.horizontal, 19)
                .frame(height: 38)
                .background(
                    SubscriberScratchPalette.orange,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 22,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 18,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 5)

            HStack(alignment: .center, spacing: 10) {
                Image("RewardsCreditToken")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                Text("1,600")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundStyle(SubscriberScratchPalette.ink)
            }

            Text("1,500 credits + 100 bonus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SubscriberScratchPalette.ink.opacity(0.64))
                .padding(.top, 2)

            Text("PAY ONCE • NEVER EXPIRES")
                .font(.system(size: 12, weight: .black))
                .tracking(0.7)
                .foregroundStyle(SubscriberScratchPalette.cream)
                .frame(maxWidth: .infinity)
                .frame(height: 39)
                .background(
                    LinearGradient(
                        colors: [SubscriberScratchPalette.ink, Color(red: 0.59, green: 0.22, blue: 0.02)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .padding(.horizontal, 25)
                .padding(.top, 12)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SubscriberScratchPalette.cream, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(SubscriberScratchPalette.orange.opacity(0.80), lineWidth: 3)
        )
        .shadow(color: SubscriberScratchPalette.orange.opacity(0.17), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Subscriber exclusive, 1,600 lifetime credits")
    }
}

private struct SubscriberScratchPrimaryButton: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
            Text(title)
                .font(.system(size: 19, weight: .black))
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 23)
        .frame(maxWidth: .infinity)
        .frame(height: 61)
        .background(
            LinearGradient(
                colors: [SubscriberScratchPalette.ink, Color(red: 0.44, green: 0.17, blue: 0.015)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: Capsule()
        )
        .shadow(color: SubscriberScratchPalette.ink.opacity(0.20), radius: 14, y: 7)
    }
}

private struct SubscriberCardGlow: View {
    @State private var glowing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 25, style: .continuous)
            .stroke(.white.opacity(glowing ? 0.10 : 0.76), lineWidth: 4)
            .shadow(color: SubscriberScratchPalette.gold.opacity(glowing ? 0.12 : 0.56), radius: glowing ? 5 : 20)
            .padding(3)
            .onAppear {
                withAnimation(.easeOut(duration: 0.85)) {
                    glowing = true
                }
            }
    }
}

private enum ScratchCoatingStyle {
    case gold
    case coral

    var colors: [Color] {
        switch self {
        case .gold:
            [
                Color(red: 1.00, green: 0.83, blue: 0.25),
                Color(red: 0.98, green: 0.63, blue: 0.08)
            ]
        case .coral:
            [
                Color(red: 1.00, green: 0.58, blue: 0.34),
                Color(red: 0.98, green: 0.31, blue: 0.22)
            ]
        }
    }

    var textColor: Color {
        switch self {
        case .gold: SubscriberScratchPalette.ink.opacity(0.82)
        case .coral: .white.opacity(0.92)
        }
    }
}

private struct SmoothScratchCard<Content: View>: View {
    let style: ScratchCoatingStyle
    let accessibilityIdentifier: String
    let onReveal: () -> Void
    @ViewBuilder let content: Content

    @State private var strokes: [[CGPoint]] = []
    @State private var isDragging = false
    @State private var scratchedCells = Set<Int>()
    @State private var isComplete = false
    @State private var coatingOpacity = 1.0
    @State private var hasStartedScratching = false

    private let gridColumns = 32
    private let gridRows = 20
    private let brushDiameter: CGFloat = 52
    private let completionThreshold = 0.34

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                content

                Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                    drawCoating(context: &context, size: size)
                    eraseStrokes(context: &context)
                }
                .compositingGroup()
                .opacity(coatingOpacity)
                .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .gesture(scratchGesture(size: proxy.size))
                .allowsHitTesting(!isComplete)

                if !hasStartedScratching && !isComplete {
                    ScratchHandHint()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scratch to reveal")
        .accessibilityHint("Drag across the card until the reward is revealed")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func drawCoating(context: inout GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: style.colors),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: size.height)
            )
        )

        context.opacity = 0.13
        for offset in stride(from: -size.height, through: size.width, by: 12) {
            var line = Path()
            line.move(to: CGPoint(x: offset, y: 0))
            line.addLine(to: CGPoint(x: offset + size.height, y: size.height))
            context.stroke(line, with: .color(.white), lineWidth: 3)
        }
        context.opacity = 1

        var title = context.resolve(
            Text("SCRATCH TO REVEAL")
                .font(.system(size: 25, weight: .black, design: .rounded))
        )
        title.shading = .color(style.textColor)
        context.draw(title, at: CGPoint(x: size.width / 2, y: size.height / 2 + 13))

        var hint = context.resolve(
            Text("✦  DRAG YOUR FINGER  ✦")
                .font(.system(size: 15, weight: .bold))
        )
        hint.shading = .color(style.textColor.opacity(0.66))
        context.draw(hint, at: CGPoint(x: size.width / 2, y: size.height / 2 - 17))
    }

    private func eraseStrokes(context: inout GraphicsContext) {
        context.blendMode = .destinationOut

        for stroke in strokes {
            guard let first = stroke.first else { continue }
            if stroke.count == 1 {
                let rect = CGRect(
                    x: first.x - brushDiameter / 2,
                    y: first.y - brushDiameter / 2,
                    width: brushDiameter,
                    height: brushDiameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(.white))
                continue
            }

            var path = Path()
            path.move(to: first)
            for point in stroke.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(
                path,
                with: .color(.white),
                style: StrokeStyle(
                    lineWidth: brushDiameter,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private func scratchGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                appendScratchPoint(value.location, in: size)
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    private func appendScratchPoint(_ point: CGPoint, in size: CGSize) {
        guard !isComplete,
              size.width > 0,
              size.height > 0 else { return }

        let clamped = CGPoint(
            x: min(max(point.x, 0), size.width),
            y: min(max(point.y, 0), size.height)
        )

        if !hasStartedScratching {
            withAnimation(.easeOut(duration: 0.16)) {
                hasStartedScratching = true
            }
        }

        var addedPoints: [CGPoint]
        if !isDragging || strokes.isEmpty {
            isDragging = true
            strokes.append([clamped])
            addedPoints = [clamped]
        } else {
            var activeStroke = strokes.removeLast()
            let start = activeStroke.last ?? clamped
            let distance = hypot(clamped.x - start.x, clamped.y - start.y)
            let stepCount = max(Int(ceil(distance / 5)), 1)
            addedPoints = (1...stepCount).map { step in
                let fraction = CGFloat(step) / CGFloat(stepCount)
                return CGPoint(
                    x: start.x + (clamped.x - start.x) * fraction,
                    y: start.y + (clamped.y - start.y) * fraction
                )
            }
            activeStroke.append(contentsOf: addedPoints)
            strokes.append(activeStroke)
        }

        updateCoverage(with: addedPoints, size: size)
    }

    private func updateCoverage(with points: [CGPoint], size: CGSize) {
        var updated = scratchedCells
        let radius = brushDiameter / 2
        let cellWidth = size.width / CGFloat(gridColumns)
        let cellHeight = size.height / CGFloat(gridRows)

        for point in points {
            let minColumn = max(Int((point.x - radius) / cellWidth), 0)
            let maxColumn = min(Int((point.x + radius) / cellWidth), gridColumns - 1)
            let minRow = max(Int((point.y - radius) / cellHeight), 0)
            let maxRow = min(Int((point.y + radius) / cellHeight), gridRows - 1)

            guard minColumn <= maxColumn, minRow <= maxRow else { continue }
            for row in minRow...maxRow {
                for column in minColumn...maxColumn {
                    let center = CGPoint(
                        x: (CGFloat(column) + 0.5) * cellWidth,
                        y: (CGFloat(row) + 0.5) * cellHeight
                    )
                    guard hypot(center.x - point.x, center.y - point.y) <= radius else {
                        continue
                    }
                    updated.insert(row * gridColumns + column)
                }
            }
        }

        scratchedCells = updated
        let coverage = Double(updated.count) / Double(gridColumns * gridRows)
        guard coverage >= completionThreshold else { return }
        completeScratch()
    }

    private func completeScratch() {
        guard !isComplete else { return }
        isComplete = true
        isDragging = false
        withAnimation(.easeOut(duration: 0.24)) {
            coatingOpacity = 0
        }

        Task {
            try? await Task.sleep(for: .milliseconds(230))
            guard !Task.isCancelled else { return }
            onReveal()
        }
    }
}

private struct ScratchHandHint: View {
    @State private var slidesRight = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.42))
                .frame(width: 55, height: 55)
                .blur(radius: 1)

            Image(systemName: "hand.draw.fill")
                .font(.system(size: 33, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
        }
        .rotationEffect(.degrees(-18))
        .offset(
            x: slidesRight ? 80 : -80,
            y: slidesRight ? 17 : -17
        )
        .animation(
            .easeInOut(duration: 1.05).repeatForever(autoreverses: true),
            value: slidesRight
        )
        .onAppear {
            slidesRight = true
        }
    }
}

private struct SubscriberScratchCelebration: View {
    let key: Int
    @State private var expanded = false

    private let colors: [Color] = [
        .yellow,
        .orange,
        .pink,
        .mint,
        .cyan,
        .purple
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<32, id: \.self) { index in
                    let angle = Double(index) / 32 * Double.pi * 2
                    let distance = CGFloat(110 + (index * 29) % 190)
                    Capsule()
                        .fill(colors[index % colors.count])
                        .frame(width: index.isMultiple(of: 3) ? 13 : 8, height: index.isMultiple(of: 3) ? 6 : 12)
                        .rotationEffect(.degrees(expanded ? Double(index * 43) : Double(index * 11)))
                        .offset(
                            x: expanded ? cos(angle) * distance : 0,
                            y: expanded ? sin(angle) * distance : 0
                        )
                        .opacity(expanded ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1.05)
                                .delay(Double(index % 6) * 0.012),
                            value: expanded
                        )
                }
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.43)
        }
        .id(key)
        .onAppear {
            expanded = true
        }
    }
}

#Preview("Subscriber Scratch Flow") {
    SubscriberScratchOfferView(
        onRewardClaimed: {},
        claimOverride: {
            try await Task.sleep(for: .milliseconds(300))
        }
    )
}
