import AVFoundation
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

enum ReturningOfferInitialPresentation: Equatable {
    case family
    case retention
    case checkingTrialEligibility

    static func select(startsAtTrial: Bool, startsAtRetention: Bool) -> Self {
        if startsAtTrial { return .checkingTrialEligibility }
        if startsAtRetention { return .retention }
        return .family
    }
}

struct ReturningUserOfferFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isSubscribed") private var isSubscribed = false

    @State private var screen: ReturningOfferScreen = .family
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseAlert: ReturningOfferPurchaseAlert?
    @State private var legalDocument: LegalDocument?
    @State private var isTrialEligible = false
    @State private var isCheckingInitialTrialEligibility: Bool
    @StateObject private var priceStore = StoreProductPriceStore.shared

    private let designSize = CGSize(width: 430, height: 932)
    private let analyticsSource: String
    private let startsAtTrial: Bool

    init(
        startsAtTrial: Bool = false,
        startsAtRetention: Bool = false,
        analyticsSource: String = "returning_offer"
    ) {
        self.analyticsSource = analyticsSource
        self.startsAtTrial = startsAtTrial
        let initialPresentation = ReturningOfferInitialPresentation.select(
            startsAtTrial: startsAtTrial,
            startsAtRetention: startsAtRetention
        )
        let initialScreen: ReturningOfferScreen
        switch initialPresentation {
        case .family:
            initialScreen = .family
        case .retention:
            initialScreen = .retention
        case .checkingTrialEligibility:
            initialScreen = .trial
        }
        _screen = State(initialValue: initialScreen)
        _isCheckingInitialTrialEligibility = State(
            initialValue: initialPresentation == .checkingTrialEligibility
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = ReturningOfferCanvasLayout(
                source: designSize,
                destination: proxy.size
            )

            ZStack {
                Color.black

                if isCheckingInitialTrialEligibility {
                    StorePurchaseLoadingOverlay(
                        accessibilityLabel: "Checking free trial eligibility"
                    )
                        .accessibilityIdentifier("returning-trial-eligibility-loading")
                } else {
                    if screen == .family {
                        familyOfferBackground(size: proxy.size)
                    }

                    ScrollView(.vertical) {
                        ZStack {
                            if screen != .family {
                                fittedOfferArtwork(using: layout)
                            }

                            if screen == .family {
                                familyOfferContent(using: layout)
                            } else if screen == .trial {
                                trialOfferContent(using: layout)
                            } else {
                                Color.black.opacity(0.55)
                                    .frame(
                                        width: designSize.width,
                                        height: designSize.height
                                    )
                                    .scaleEffect(layout.scale)
                                    .position(layout.center)
                                    .accessibilityHidden(true)
                                retentionCopyCorrections(using: layout)
                            }

                            controls(using: layout)
                        }
                        .frame(
                            width: proxy.size.width,
                            height: layout.contentHeight
                        )
                    }
                    .scrollIndicators(.hidden)

                    if isPurchasing || isRestoring {
                        StorePurchaseLoadingOverlay(
                            accessibilityLabel: isRestoring
                                ? "Restoring App Store purchases"
                                : "Processing App Store purchase"
                        )
                            .transition(.opacity)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .presentationBackground(.clear)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.light)
        .onAppear {
            if !isCheckingInitialTrialEligibility {
                trackPaywallScreen()
            }
        }
        .onChange(of: screen) { _, _ in
            if !isCheckingInitialTrialEligibility {
                trackPaywallScreen()
            }
        }
        .onChange(of: isCheckingInitialTrialEligibility) { wasChecking, isChecking in
            if wasChecking, !isChecking {
                trackPaywallScreen()
            }
        }
        .alert(item: $purchaseAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .fullScreenCover(item: $legalDocument) { document in
            InAppBrowserView(url: document.url)
                .ignoresSafeArea()
        }
        .task {
            let familyID = SubscriptionProductID.familyExclusiveWeekly.rawValue
            let trialID = SubscriptionProductID.threeDayFreeTrialYearly.rawValue
            await priceStore.load(productIDs: [familyID, trialID])
            let trialEligible = await priceStore.isEligibleForIntroOffer(productID: trialID)
            guard !Task.isCancelled else { return }
            isTrialEligible = trialEligible
            if startsAtTrial {
                if trialEligible {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCheckingInitialTrialEligibility = false
                    }
                } else {
                    dismiss()
                }
            }
        }
    }

    private func familyOfferBackground(size: CGSize) -> some View {
        ZStack {
            Color.black

            LoopingVideoView(
                resourceName: "ReturningOfferFamilyBackgroundVideo",
                videoGravity: .resizeAspectFill
            )
            .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.20), location: 0),
                    .init(color: .clear, location: 0.30),
                    .init(color: .black.opacity(0.16), location: 0.43),
                    .init(color: Color(red: 0.24, green: 0.08, blue: 0.03).opacity(0.62), location: 0.67),
                    .init(color: Color(red: 0.12, green: 0.03, blue: 0.02).opacity(0.90), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func fittedOfferArtwork(using layout: ReturningOfferCanvasLayout) -> some View {
        Image(screen.assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: designSize.width, height: designSize.height)
            .scaleEffect(layout.scale)
            .position(layout.center)
            .accessibilityHidden(true)
    }

    private func familyOfferContent(using layout: ReturningOfferCanvasLayout) -> some View {
        familyOfferDesign
            .frame(width: designSize.width, height: designSize.height)
            .scaleEffect(layout.scale)
            .position(layout.center)
            .allowsHitTesting(false)
    }

    private func trialOfferContent(using layout: ReturningOfferCanvasLayout) -> some View {
        trialOfferDesign
            .frame(width: designSize.width, height: designSize.height)
            .scaleEffect(layout.scale)
            .position(layout.center)
            .allowsHitTesting(false)
    }

    private func retentionCopyCorrections(using layout: ReturningOfferCanvasLayout) -> some View {
        // The retention artwork contains legacy numeric marketing claims.
        // Cover only those baked-in labels while preserving the rest of the asset pixel-for-pixel.
        ZStack {
            retentionCopyPatch("Customizable Styles")
                .position(x: 190, y: 585)

            retentionCopyPatch("Create More Every Week")
                .position(x: 190, y: 634)

            // The source artwork contains a full-width CTA. Restore the card's
            // vertical gradient first so the live CTA can use a calmer size.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.961, green: 0.839, blue: 0.631),
                            Color(red: 0.953, green: 0.816, blue: 0.580),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 382, height: 80)
                .position(x: 215, y: 723)

            Text("Pro Weekly • \(weeklyOfferPriceLabel) • Auto-renews weekly until canceled")
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(Color(red: 0.27, green: 0.20, blue: 0.14))
                .position(x: 215, y: 674)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("returning-retention-subscription-details")

            HStack(spacing: 0) {
                Spacer()
                Text(weeklyOfferButtonTitle)
                    .font(.system(size: 17, weight: .bold))
                    .minimumScaleFactor(0.80)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 19, weight: .bold))
                    .padding(.trailing, 18)
            }
            .foregroundStyle(.white)
            .frame(width: 330, height: 52)
            .background(
                LinearGradient(
                    colors: retentionButtonColors,
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .position(x: 215, y: 722)

            HStack(spacing: 5) {
                Text("Restore Purchases")
                    .underline()
                Text("|")
                    .accessibilityHidden(true)
                Text("Privacy Policy")
                    .underline()
                Text("|")
                    .accessibilityHidden(true)
                Text("Terms of Use")
                    .underline()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(red: 0.31, green: 0.23, blue: 0.16).opacity(0.82))
            .position(x: 215, y: 769)
        }
        .frame(width: designSize.width, height: designSize.height)
        .scaleEffect(layout.scale)
        .position(layout.center)
        .allowsHitTesting(false)
    }

    private func retentionCopyPatch(_ title: String) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.988, green: 0.961, blue: 0.918),
                            Color(red: 0.980, green: 0.918, blue: 0.820),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(red: 0.12, green: 0.11, blue: 0.10))
                .padding(.leading, 4)
        }
        .frame(width: 210, height: 34)
    }

    private var trialOfferDesign: some View {
        let productID = SubscriptionProductID.threeDayFreeTrialYearly.rawValue
        let period = priceStore.introductoryPeriodDescription(for: productID) ?? "Free trial"
        let renewalPrice = priceStore.displayPrice(for: productID)
        let weeklyPrice = priceStore.periodicPrice(
            for: productID,
            divisor: 52,
            suffix: "/week"
        )

        return ZStack {
            Image(systemName: "xmark")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.brown.opacity(0.72), in: Circle())
                .position(x: 34, y: 65)

            VStack(spacing: 4) {
                Text("PREMIUM")
                    .font(.system(size: 21, weight: .black))
                    .foregroundStyle(Color(red: 1, green: 0.22, blue: 0.12))
                Text("\(period.capitalized) Free Trial")
                    .font(.system(size: 31, weight: .black))
                    .foregroundStyle(Color(red: 0.28, green: 0.20, blue: 0.14))
                Text("Try every premium feature before you subscribe")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.62))
            }
            .position(x: 215, y: 374)

            VStack(alignment: .leading, spacing: 14) {
                trialTimelineRow(
                    icon: "lock.open.fill",
                    title: "Today",
                    detail: "Premium access begins"
                )
                trialTimelineRow(
                    icon: "calendar.badge.clock",
                    title: "During the trial",
                    detail: "Cancel anytime in your App Store settings"
                )
                trialTimelineRow(
                    icon: "star.fill",
                    title: "After \(period)",
                    detail: "Renews for \(renewalPrice) per year"
                )
            }
            .padding(20)
            .frame(width: 390, height: 228, alignment: .leading)
            .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.86), lineWidth: 1))
            .position(x: 215, y: 552)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Annual membership")
                        .font(.system(size: 18, weight: .bold))
                    Text("12 months of premium access")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
                Spacer()
                Text(period.capitalized + " Free")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(Color(red: 1, green: 0.26, blue: 0.16))
            }
            .padding(.horizontal, 19)
            .frame(width: 390, height: 86)
            .background(Color.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.orange, lineWidth: 1.4))
            .position(x: 215, y: 708)

            HStack {
                Spacer()
                Text("Start My Free Trial")
                    .font(.system(size: 21, weight: .bold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 23, weight: .bold))
                    .padding(.trailing, 22)
            }
            .foregroundStyle(.white)
            .frame(width: 382, height: 66)
            .background(
                LinearGradient(
                    colors: [Color.orange, Color(red: 1, green: 0.20, blue: 0.12)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .position(x: 215, y: 806)

            Text("\(period.capitalized) free, then \(renewalPrice)/year (\(weeklyPrice))")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.52))
                .position(x: 215, y: 854)

            HStack(spacing: 13) {
                Text("Privacy Policy").underline()
                Text("|")
                Text("Terms of Use").underline()
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.58))
            .position(x: 215, y: 891)
        }
    }

    private func trialTimelineRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.orange, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 0.36, green: 0.22, blue: 0.12))
                Text(detail)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.58))
                    .lineLimit(2)
            }
        }
    }

    private var familyOfferDesign: some View {
        ZStack {
            Image(systemName: "xmark")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.22), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.76), lineWidth: 1))
                .position(x: 37, y: 65)

            VStack(spacing: 5) {
                Text("Family Exclusive")
                    .font(.system(size: 31, weight: .heavy))
                    .shadow(color: offerRed.opacity(0.96), radius: 0, x: 0, y: 2)

                Text("Special offer for your family's memories")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .position(x: 215, y: 397)

            familyOfferCard
                .frame(width: 390, height: 282)
                .position(x: 215, y: 620)

            HStack(spacing: 0) {
                Spacer()
                Text("Claim My Offer")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 24, weight: .semibold))
                    .padding(.trailing, 24)
            }
            .foregroundStyle(.white)
            .frame(width: 382, height: 70)
            .background(offerRed, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.black.opacity(0.68), lineWidth: 1)
            )
            .position(x: 215, y: 839)

            HStack(spacing: 13) {
                Text("Privacy Policy").underline()
                Text("|")
                Text("Terms of Use").underline()
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.82))
            .position(x: 215, y: 890)
        }
    }

    private var familyOfferCard: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .light)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.48))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.88), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text("Exclusive Weekly Offer")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 27)
                    .background(offerRed, in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(
                        priceStore.periodicPrice(
                            for: SubscriptionProductID.familyExclusiveWeekly.rawValue,
                            divisor: 7,
                            suffix: ""
                        )
                    )
                        .font(.system(size: 49, weight: .heavy))
                    Text("per day")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(offerRed)
                .shadow(color: .white.opacity(0.72), radius: 1, y: 1)
                .frame(height: 58)

                Text("\(priceStore.displayPrice(for: SubscriptionProductID.familyExclusiveWeekly.rawValue))/week")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.82))

                VStack(alignment: .leading, spacing: 11) {
                    familyFeatureRow(highlight: "400", suffix: " Credits Per week")
                    familyFeatureRow(highlight: nil, suffix: "Priority & Customizable Styles")
                    familyFeatureRow(highlight: nil, suffix: "Ad-free & No Watermark")
                    familyFeatureRow(highlight: nil, suffix: "Create More Every Week")
                }
                .padding(.top, 14)
            }
            .padding(.leading, 20)
            .padding(.top, 17)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Image(systemName: "gift.fill")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange, Color.pink, offerRed],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.20), radius: 7, y: 5)
                .padding(.top, 12)
                .padding(.trailing, 18)
        }
    }

    private func familyFeatureRow(
        highlight: String?,
        suffix: String,
        prefix: String = ""
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(offerRed)
                .frame(width: 18)

            HStack(spacing: 0) {
                if !prefix.isEmpty {
                    Text(prefix)
                }
                if let highlight {
                    Text(highlight)
                        .fontWeight(.heavy)
                        .foregroundStyle(offerRed)
                }
                Text(suffix)
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.82))
        }
    }

    private var offerRed: Color {
        Color(red: 0.93, green: 0.24, blue: 0.17)
    }

    @ViewBuilder
    private func controls(using layout: ReturningOfferCanvasLayout) -> some View {
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

            privacyHotspot(using: layout)
            termsHotspot(using: layout)

        case .retention:
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 18 * layout.scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38 * layout.scale, height: 38 * layout.scale)
                    .background(Color.black.opacity(0.38), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .position(layout.point(CGPoint(x: 39, y: 170)))
            .disabled(isPurchasing || isRestoring)
            .accessibilityLabel("Close discount offer")
            .accessibilityIdentifier("returning-retention-close")

            hotspot(
                label: weeklyOfferButtonTitle,
                identifier: "returning-retention-continue",
                center: CGPoint(x: 215, y: 722),
                size: CGSize(width: 330, height: 56),
                layout: layout,
                isEnabled: isWeeklyOfferAvailable
            ) {
                beginPurchase(.weekly, origin: .retention)
            }

            hotspot(
                label: "Restore Purchases",
                identifier: "returning-retention-restore",
                center: CGPoint(x: 105, y: 769),
                size: CGSize(width: 120, height: 30),
                layout: layout,
                action: restorePurchases
            )

            hotspot(
                label: "Privacy Policy",
                identifier: "returning-retention-privacy",
                center: CGPoint(x: 235, y: 769),
                size: CGSize(width: 96, height: 30),
                layout: layout
            ) {
                legalDocument = .privacyPolicy
            }

            hotspot(
                label: "Terms of Use",
                identifier: "returning-retention-terms",
                center: CGPoint(x: 338, y: 769),
                size: CGSize(width: 92, height: 30),
                layout: layout
            ) {
                legalDocument = .termsOfService
            }

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
                center: CGPoint(x: 215, y: 806),
                size: CGSize(width: 382, height: 70),
                layout: layout
            ) {
                beginPurchase(.annual, origin: .trial)
            }

            privacyHotspot(using: layout)
            termsHotspot(using: layout)

        }
    }

    private func privacyHotspot(using layout: ReturningOfferCanvasLayout) -> some View {
        hotspot(
            label: "Privacy Policy",
            identifier: "returning-offer-privacy",
            center: CGPoint(x: 145, y: 890),
            size: CGSize(width: 130, height: 34),
            layout: layout
        ) {
            legalDocument = .privacyPolicy
        }
    }

    private func termsHotspot(using layout: ReturningOfferCanvasLayout) -> some View {
        hotspot(
            label: "Terms of Use",
            identifier: "returning-offer-terms",
            center: CGPoint(x: 285, y: 890),
            size: CGSize(width: 150, height: 34),
            layout: layout
        ) {
            legalDocument = .termsOfService
        }
    }

    private func hotspot(
        label: String,
        identifier: String,
        center: CGPoint,
        size: CGSize,
        layout: ReturningOfferCanvasLayout,
        isEnabled: Bool = true,
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
        .disabled(isPurchasing || isRestoring || !isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var weeklyOfferPrice: String? {
        priceStore.loadedDisplayPrice(for: SubscriptionProductID.familyExclusiveWeekly.rawValue)
    }

    private var isWeeklyOfferAvailable: Bool {
        weeklyOfferPrice != nil
    }

    private var weeklyOfferPriceLabel: String {
        weeklyOfferPrice.map { "\($0)/week" } ?? "Loading price…"
    }

    private var weeklyOfferButtonTitle: String {
        weeklyOfferPrice.map { "Subscribe • \($0)/week" } ?? "Loading price…"
    }

    private var retentionButtonColors: [Color] {
        if isWeeklyOfferAvailable {
            return [
                Color(red: 1, green: 0.34, blue: 0.29),
                Color(red: 1, green: 0.22, blue: 0.16),
            ]
        }
        return [
            Color(red: 1, green: 0.47, blue: 0.42),
            Color(red: 1, green: 0.36, blue: 0.31),
        ]
    }

    private func showTrial() {
        guard isTrialEligible else {
            dismiss()
            return
        }
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
        guard !isPurchasing, !isRestoring else { return }

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

    private func restorePurchases() {
        guard !isPurchasing, !isRestoring else { return }
        isRestoring = true

        Task {
            let outcome = await SubscriptionPurchaseService.restore()
            isRestoring = false

            switch outcome {
            case .purchased:
                isSubscribed = true
                dismiss()
            case .unavailable:
                purchaseAlert = ReturningOfferPurchaseAlert(
                    title: "No Purchases Found",
                    message: "No active subscription was found for this Apple ID."
                )
            case .failed(let message):
                purchaseAlert = ReturningOfferPurchaseAlert(
                    title: "Restore Unavailable",
                    message: message
                )
            case .cancelled, .pending:
                break
            }
        }
    }

    private func finishCancelledPurchase(from origin: ReturningOfferPurchaseOrigin) {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch origin {
            case .family, .retention:
                screen = .retention
            case .trial:
                if isTrialEligible { screen = .trial }
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
                        onClose: dismiss.callAsFunction,
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

struct ReturningOfferCanvasLayout {
    let scale: CGFloat
    let origin: CGPoint
    let renderedSize: CGSize
    let contentHeight: CGFloat

    var center: CGPoint {
        CGPoint(
            x: origin.x + renderedSize.width / 2,
            y: origin.y + renderedSize.height / 2
        )
    }

    init(source: CGSize, destination: CGSize) {
        guard source.width > 0,
              source.height > 0,
              destination.width > 0,
              destination.height > 0 else {
            scale = 1
            renderedSize = source
            contentHeight = max(source.height, destination.height)
            origin = .zero
            return
        }

        let widthScale = min(1, destination.width / source.width)
        let fittedScale = min(widthScale, destination.height / source.height)

        // Portrait presentations fit the complete purchase decision on screen.
        // Short or landscape windows keep a readable width and scroll vertically.
        scale = destination.width > destination.height ? widthScale : fittedScale
        renderedSize = CGSize(width: source.width * scale, height: source.height * scale)
        contentHeight = max(destination.height, renderedSize.height)
        origin = CGPoint(
            x: (destination.width - renderedSize.width) / 2,
            y: (contentHeight - renderedSize.height) / 2
        )
    }

    func point(_ sourcePoint: CGPoint) -> CGPoint {
        CGPoint(
            x: origin.x + sourcePoint.x * scale,
            y: origin.y + sourcePoint.y * scale
        )
    }
}

#Preview {
    ReturningUserOfferFlowView()
}
