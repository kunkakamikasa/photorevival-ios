import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UserNotifications

enum PaywallLayoutPolicy {
    static let minimumReadableScale: CGFloat = 0.78

    static func scale(
        containerSize: CGSize,
        designWidth: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        guard containerSize.width > 0,
              containerSize.height > 0,
              designWidth > 0,
              contentHeight > 0 else { return 1 }

        let widthScale = containerSize.width / designWidth
        let heightScale = containerSize.height / contentHeight

        // Fit the full purchase decision into ordinary portrait windows while
        // retaining readable controls and vertical scrolling in short windows.
        return min(1, widthScale, max(heightScale, minimumReadableScale))
    }
}

struct MembershipPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("isSubscribed") private var isSubscribed = false
    @AppStorage("isLoggedIn") private var storedIsLoggedIn = false
    let onClose: (() -> Void)?
    private let isLoggedInOverride: Bool?
    private let showsFirstLaunchVideoBackground: Bool
    private let analyticsSource: String
    private let upgradingFromLevel: SubscriptionPlanLevel?
    @State private var tier: MembershipTier
    @State private var billing: MembershipBilling
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseAlert: SubscriptionPurchaseAlert?
    @State private var legalDocument: LegalDocument?
    @StateObject private var priceStore = StoreProductPriceStore.shared

    private let designWidth: CGFloat = 430
    private let designHeight: CGFloat = 862
    private let loggedInDesignHeight: CGFloat = 932
    private let firstLaunchVideoAspectRatio: CGFloat = 1320.0 / 1170.0
    private let firstLaunchVideoTopCrop: CGFloat = 32

    init(
        isLoggedIn: Bool? = nil,
        showsFirstLaunchVideoBackground: Bool = false,
        analyticsSource: String = "membership_entry",
        upgradingFromProductID: String? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.isLoggedInOverride = isLoggedIn
        self.showsFirstLaunchVideoBackground = showsFirstLaunchVideoBackground
        self.analyticsSource = analyticsSource
        let upgradingFromLevel = SubscriptionPlanLevel(productID: upgradingFromProductID)
        self.upgradingFromLevel = upgradingFromLevel
        _tier = State(initialValue: upgradingFromLevel == nil ? .pro : .proPlus)
        _billing = State(initialValue: .annual)
        self.onClose = onClose
    }

    private var usesLoggedInPaywall: Bool {
        (isLoggedInOverride ?? storedIsLoggedIn)
            || ProcessInfo.processInfo.arguments.contains("-loggedIn")
    }

    private var usesFirstLaunchVideoBackground: Bool {
        showsFirstLaunchVideoBackground && !usesLoggedInPaywall
    }

    private var promotionContext: AppAnalytics.PromotionContext {
        let variant = usesLoggedInPaywall ? "membership_signed_in" : "membership_guest"
        return AppAnalytics.PromotionContext(
            promotionID: variant,
            promotionName: "membership",
            creativeName: variant,
            creativeSlot: analyticsSource,
            offerVariant: tier.rawValue,
            billingPeriod: billing.rawValue
        )
    }

    private var visibleLoggedInTiers: [MembershipTier] {
        guard upgradingFromLevel != nil else { return MembershipTier.allCases }
        return MembershipTier.allCases.filter { option in
            MembershipBilling.allCases.contains { isUpgradeOption(tier: option, billing: $0) }
        }
    }

    private func isUpgradeOption(
        tier optionTier: MembershipTier,
        billing optionBilling: MembershipBilling
    ) -> Bool {
        guard let upgradingFromLevel else { return true }
        return optionBilling.planLevel(for: optionTier) > upgradingFromLevel
    }

    private func selectTier(_ option: MembershipTier) {
        guard visibleLoggedInTiers.contains(option) else { return }
        tier = option
        if !isUpgradeOption(tier: option, billing: billing),
           let firstUpgrade = MembershipBilling.allCases.first(where: {
               isUpgradeOption(tier: option, billing: $0)
           }) {
            billing = firstUpgrade
        }
    }

    private var paywallHeaderHeight: CGFloat {
        usesFirstLaunchVideoBackground
            ? designWidth / firstLaunchVideoAspectRatio
            : 310
    }

    private var activeContentHeight: CGFloat {
        if usesLoggedInPaywall {
            return loggedInDesignHeight
        }
        guard usesFirstLaunchVideoBackground else {
            return designHeight
        }
        return designHeight + paywallHeaderHeight - 310 - 58
    }

    var body: some View {
        GeometryReader { proxy in
            let contentHeight = activeContentHeight
            let bottomClearance = max(proxy.safeAreaInsets.bottom, 20)
            let visibleContentSize = CGSize(
                width: proxy.size.width,
                height: max(proxy.size.height - bottomClearance, 1)
            )
            let scale = PaywallLayoutPolicy.scale(
                containerSize: visibleContentSize,
                designWidth: designWidth,
                contentHeight: contentHeight
            )
            let scaledWidth = designWidth * scale
            let scaledHeight = contentHeight * scale

            ZStack(alignment: .topLeading) {
                paywallBackground

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)

                            Group {
                                if usesLoggedInPaywall {
                                    loggedInPaywallContent
                                } else {
                                    paywallContent
                                }
                            }
                            .frame(width: designWidth, height: contentHeight, alignment: .top)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(
                                width: scaledWidth,
                                height: scaledHeight,
                                alignment: .topLeading
                            )

                            Spacer(minLength: 0)
                        }
                        .frame(
                            minWidth: proxy.size.width,
                            minHeight: visibleContentSize.height,
                            alignment: .top
                        )

                        Color.clear
                            .frame(height: bottomClearance)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)

                if isPurchasing || isRestoring {
                    StorePurchaseLoadingOverlay(
                        accessibilityLabel: isRestoring
                            ? "Restoring App Store purchases"
                            : "Processing App Store purchase"
                    )
                }
            }
        }
        .ignoresSafeArea(edges: usesLoggedInPaywall ? .all : .bottom)
        .preferredColorScheme(.dark)
        .onAppear {
            AppAnalytics.paywallViewed(
                variant: usesLoggedInPaywall ? "membership_signed_in" : "membership_guest",
                source: analyticsSource,
                productID: billing.productIdentifier(
                    for: tier,
                    isLoggedIn: usesLoggedInPaywall
                ).rawValue,
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
        .fullScreenCover(item: $legalDocument) { document in
            InAppBrowserView(url: document.url)
                .ignoresSafeArea()
        }
        .task(id: paywallPriceLoadID) {
            guard scenePhase == .active else { return }
            await priceStore.loadWithRetry(productIDs: paywallProductIDs)
        }
    }

    private var paywallProductIDs: [String] {
        MembershipTier.allCases.flatMap { tier in
            MembershipBilling.allCases.map { billing in
                billing.productIdentifier(
                    for: tier,
                    isLoggedIn: usesLoggedInPaywall
                ).rawValue
            }
        }
    }

    private var paywallPriceLoadID: String {
        "\(scenePhase)-\(paywallProductIDs.sorted().joined(separator: ","))"
    }

    private var paywallContent: some View {
        VStack(spacing: 0) {
            paywallHeader
                .frame(width: designWidth, height: paywallHeaderHeight)

            // Keep the complete purchase decision, including legal links, on
            // screen in iPhone compatibility mode on iPad.
            Color.clear.frame(height: usesFirstLaunchVideoBackground ? 0 : 12)

            benefitSection
                .frame(width: designWidth, height: 184, alignment: .top)

            Color.clear.frame(height: 32)

            membershipPlanRow(.annual)
                .frame(width: 390, height: 64)

            Color.clear.frame(height: 10)

            membershipPlanRow(.weekly)
                .frame(width: 390, height: 70)

            Color.clear.frame(height: 26)

            continueButton
                .frame(width: 390, height: 64)

            Color.clear.frame(height: 20)

            footerLinks
                .frame(width: 390, height: 22)
        }
    }

    private var loggedInPaywallContent: some View {
        ZStack(alignment: .top) {
            loggedInHero

            VStack(spacing: 0) {
                Color.clear.frame(height: 280)

                loggedInTierCarousel
                    .frame(width: designWidth, height: 242)

                Color.clear.frame(height: 12)

                loggedInMembershipPlanRow(.annual)
                    .frame(width: 390, height: 82)

                Color.clear.frame(height: 12)

                loggedInMembershipPlanRow(.weekly)
                    .frame(width: 390, height: 82)

                Color.clear.frame(height: 10)

                loggedInRefundGuarantee
                    .frame(width: 390, height: 24)

                Color.clear.frame(height: 10)

                loggedInContinueButton
                    .frame(width: 390, height: 64)

                Color.clear.frame(height: 0)

                footerLinks
                    .frame(width: 390, height: 22)
            }
        }
        .frame(width: designWidth, height: loggedInDesignHeight, alignment: .top)
    }

    private var loggedInHero: some View {
        ZStack(alignment: .top) {
            LoopingVideoView(
                resourceName: "LoggedInPaywallBackgroundVideo",
                videoGravity: .resizeAspectFill
            )
            .frame(width: designWidth, height: 382)
            .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.12), location: 0),
                    .init(color: .clear, location: 0.48),
                    .init(color: Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.98), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Button(action: closePaywall) {
                Image(systemName: "xmark")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.24), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.78), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .position(x: 37, y: 76)
            .accessibilityLabel("Close membership")

            Button(action: restorePurchases) {
                Text(isRestoring ? "Restoring..." : "Restore")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 82, height: 36)
                    .background(.black.opacity(0.24), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.78), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isRestoring || isPurchasing)
            .position(x: 370, y: 76)
            .accessibilityLabel("Restore")
        }
        .frame(width: designWidth, height: 382)
        .clipped()
    }

    private var loggedInTierCarousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(visibleLoggedInTiers) { option in
                    VStack(spacing: 0) {
                        loggedInTierHeading(option)
                            .frame(height: 52)

                        Button {
                            withAnimation(.snappy(duration: 0.30, extraBounce: 0.06)) {
                                selectTier(option)
                            }
                        } label: {
                            loggedInBenefitCard(option)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(tier == option ? .isSelected : [])
                        .accessibilityIdentifier("membership-tier-\(option.rawValue)")
                    }
                    .frame(width: 315, height: 242, alignment: .top)
                    .id(option)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.leading, 18, for: .scrollContent)
        .contentMargins(.trailing, 70, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: tierScrollPosition, anchor: .leading)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("membership-tier-carousel")
    }

    private var tierScrollPosition: Binding<MembershipTier?> {
        Binding(
            get: { tier },
            set: { newTier in
                guard let newTier, tier != newTier else { return }
                selectTier(newTier)
            }
        )
    }

    private func loggedInTierHeading(_ option: MembershipTier) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(option.title)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Image("RewardsCreditToken")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 27, height: 27)

                Text("\(option.weeklyCredits)/week")
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.86))
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color.black.opacity(0.52), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 1)
        .frame(width: 315, height: 52)
    }

    private func loggedInBenefitCard(_ option: MembershipTier) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Up to \(option.yearlyVideos) videos yearly")
                .font(.system(size: 16.5, weight: .regular))
                .foregroundStyle(.white)
                .padding(.bottom, 14)

            loggedInBenefitRow("Evolving & Customizable Styles", tier: option)
            loggedInBenefitRow("Ad-free & No Watermark", tier: option)
            loggedInBenefitRow("Create More Every Week", tier: option)
            loggedInBenefitRow("Parallel Generations", tier: option)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .frame(width: 315, height: 190, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.23), Color.white.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }

    private func loggedInBenefitRow(
        _ prefix: String,
        emphasis: String? = nil,
        suffix: String = "",
        tier: MembershipTier
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.white.opacity(0.12))
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(tier.planAccent)
            }
            .frame(width: 23, height: 23)

            Group {
                if let emphasis {
                    Text(prefix) + Text(emphasis).bold().foregroundColor(tier.planAccent) + Text(suffix)
                } else {
                    Text(prefix)
                }
            }
            .font(.system(size: 14.5, weight: .regular))
            .foregroundStyle(.white)
            .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(height: 34)
    }

    private func loggedInMembershipPlanRow(_ option: MembershipBilling) -> some View {
        let canSelect = isUpgradeOption(tier: tier, billing: option)

        return Button {
            guard canSelect else { return }
            billing = option
        } label: {
            HStack(spacing: 13) {
                planSelectionIndicator(isSelected: billing == option)

                VStack(alignment: .leading, spacing: option == .annual ? 4 : 0) {
                    Text(option.loggedInTitle)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)

                    if option == .annual {
                        Text(displayPrice(for: option, tier: tier, loggedIn: true))
                            .font(.system(size: 18.5, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }

                Spacer(minLength: 8)

                Text(trailingPrice(for: option, tier: tier, loggedIn: true))
                    .font(.system(size: 17.5, weight: option == .annual ? .heavy : .semibold))
                    .foregroundStyle(option == .annual ? .white : Color.white.opacity(0.72))
            }
            .padding(.horizontal, 17)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Group {
                    if billing == option {
                        LinearGradient(
                            colors: tier.planBackground,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color(red: 0.075, green: 0.082, blue: 0.088)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        billing == option ? tier.planAccent : Color.white.opacity(0.26),
                        lineWidth: billing == option ? 1.2 : 0.7
                    )
            )
            .overlay(alignment: .topTrailing) {
                if option == .annual {
                    annualDiscountBadge
                        .offset(x: -12, y: -15)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canSelect)
        .opacity(canSelect ? 1 : 0.34)
        .accessibilityLabel("\(option.loggedInTitle), \(trailingPrice(for: option, tier: tier, loggedIn: true))")
        .accessibilityValue(option.productIdentifier(for: tier, isLoggedIn: true).rawValue)
        .accessibilityAddTraits(billing == option ? .isSelected : [])
        .accessibilityIdentifier("membership-billing-\(option.rawValue)")
    }

    private var loggedInRefundGuarantee: some View {
        HStack(spacing: 6) {
            Image(systemName: "apple.logo")
                .font(.system(size: 16, weight: .medium))
            Text("Purchases are securely processed by Apple")
        }
        .font(.system(size: 13.5, weight: .regular))
        .foregroundStyle(Color.white.opacity(0.36))
    }

    private var loggedInContinueButton: some View {
        Button(action: beginPurchase) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.70, blue: 0.27), Color(red: 0.98, green: 0.25, blue: 0.17)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                Text(isPurchasing ? "Connecting..." : "Continue")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.trailing, 22)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(TemplatePressStyle())
        .disabled(
            isPurchasing || isRestoring || !isUpgradeOption(tier: tier, billing: billing)
        )
        .accessibilityIdentifier("membership-continue")
        .accessibilityValue(billing.productIdentifier(for: tier, isLoggedIn: true).rawValue)
    }

    private var paywallBackground: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: Color(red: 0.118, green: 0.118, blue: 0.118), location: 0.60),
                .init(color: Color(red: 0.118, green: 0.118, blue: 0.118), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var paywallHeader: some View {
        ZStack(alignment: .topLeading) {
            if usesFirstLaunchVideoBackground {
                Color.black

                LoopingVideoView(
                    resourceName: "FirstLaunchPaywallBackgroundVideo",
                    videoGravity: .resizeAspectFill
                )
                .frame(
                    width: designWidth,
                    height: paywallHeaderHeight + firstLaunchVideoTopCrop
                )
                .offset(y: -firstLaunchVideoTopCrop)
            } else {
                Image(tier.mediaStripAsset)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: designWidth, height: 310)
            }

            Button(action: closePaywall) {
                if usesFirstLaunchVideoBackground {
                    Image(systemName: "xmark")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.34), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.78), lineWidth: 1))
                } else {
                    Color.clear
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .position(x: 37, y: 30)
            .accessibilityLabel("Close membership")

            Button(action: restorePurchases) {
                if usesFirstLaunchVideoBackground {
                    Text(isRestoring ? "Restoring..." : "Restore")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 92, height: 38)
                        .background(.black.opacity(0.34), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1))
                } else {
                    Color.clear
                        .frame(width: 98, height: 48)
                        .contentShape(Capsule())
                }
            }
            .buttonStyle(.plain)
            .disabled(isRestoring || isPurchasing)
            .position(x: 370, y: 30)
            .accessibilityLabel("Restore")
        }
        .frame(width: designWidth, height: paywallHeaderHeight, alignment: .top)
        .clipped()
    }

    private var benefitSection: some View {
        ZStack(alignment: .top) {
            benefitPanel
                .padding(.top, 22)

            tierControl
                .zIndex(2)
        }
    }

    private var tierControl: some View {
        HStack(spacing: 0) {
            ForEach(MembershipTier.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        tier = option
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(option == .pro && tier == option ? Color(red: 0.31, green: 0.12, blue: 0.03) : .white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if tier == option {
                                LinearGradient(
                                    colors: option.tierGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .clipShape(Capsule())
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(tier == option ? .isSelected : [])
                .accessibilityIdentifier("membership-tier-\(option.rawValue)")
            }
        }
        .frame(width: 350, height: 40)
        .background(Color(red: 0.094, green: 0.098, blue: 0.106), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.7))
    }

    private var benefitPanel: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                benefitRow(stylesBenefitText)
                benefitRow(Text("Ad-free & No Watermark"))
                benefitRow(discountBenefitText)
                benefitRow(Text("Parallel Generations"))
            }

            Spacer(minLength: 0)

            VStack(spacing: 5) {
                Image("RewardsCreditToken")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 44, height: 44)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(tier.weeklyCredits)")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("/week")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .frame(width: 96)
            .offset(y: 6)
        }
        .padding(.leading, 16)
        .padding(.trailing, 13)
        .padding(.top, 45)
        .padding(.bottom, 9)
        .frame(width: 390, height: 162)
        .background(
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.20, blue: 0.20), Color(red: 0.215, green: 0.215, blue: 0.215)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(alignment: .top) {
            Text("Up to \(String(tier.yearlyVideos)) videos yearly")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.94, blue: 0.83))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Color.black.opacity(0.58), in: Capsule())
                .offset(y: 25)
        }
    }

    private var stylesBenefitText: Text {
        Text("Evolving & Customizable Styles")
    }

    private var discountBenefitText: Text {
        Text("Create More Every Week")
    }

    private func benefitRow(_ title: Text) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 15.5, weight: .black))
                .frame(width: 16)

            title
                .font(.system(size: 15.5, weight: .regular))
                .tracking(0.1)
                .lineLimit(1)
                .minimumScaleFactor(0.88)
                .allowsTightening(true)
        }
        .foregroundStyle(.white)
        .frame(height: 21)
    }

    private func membershipPlanRow(_ option: MembershipBilling) -> some View {
        Button {
            billing = option
        } label: {
            HStack(spacing: 10) {
                planSelectionIndicator(isSelected: billing == option)

                Text(option.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                if option == .annual {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(displayPrice(for: option, tier: tier, loggedIn: false))
                            .font(.system(size: 18.5, weight: .heavy))
                            .foregroundStyle(.white)
                        Text(trailingPrice(for: option, tier: tier, loggedIn: false))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                } else {
                    Text(displayPrice(for: option, tier: tier, loggedIn: false))
                        .font(.system(size: 18.5, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Group {
                    if billing == option {
                        LinearGradient(
                            colors: tier.planBackground,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color(red: 0.094, green: 0.098, blue: 0.106)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        billing == option ? tier.planAccent : Color(red: 0.36, green: 0.37, blue: 0.38),
                        lineWidth: billing == option ? 1.8 : 0.75
                    )
            )
            .overlay(alignment: .topLeading) {
                if option == .annual {
                    annualDiscountBadge
                        .offset(x: 12, y: -15)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title), \(displayPrice(for: option, tier: tier, loggedIn: false))")
        .accessibilityValue(option.productIdentifier(for: tier, isLoggedIn: usesLoggedInPaywall).rawValue)
        .accessibilityAddTraits(billing == option ? .isSelected : [])
        .accessibilityIdentifier("membership-billing-\(option.rawValue)")
    }

    private func planSelectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            if isSelected {
                Circle().fill(tier.selectionAccent)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(Color(red: 0.48, green: 0.49, blue: 0.50), lineWidth: 1.6)
            }
        }
        .frame(width: 22, height: 22)
    }

    private func displayPrice(
        for billing: MembershipBilling,
        tier: MembershipTier,
        loggedIn: Bool
    ) -> String {
        priceStore.displayPrice(
            for: billing.productIdentifier(for: tier, isLoggedIn: loggedIn).rawValue
        )
    }

    private func trailingPrice(
        for billing: MembershipBilling,
        tier: MembershipTier,
        loggedIn: Bool
    ) -> String {
        let productID = billing.productIdentifier(for: tier, isLoggedIn: loggedIn).rawValue
        if billing == .annual {
            return priceStore.periodicPrice(
                for: productID,
                divisor: 52,
                suffix: "/week"
            )
        }
        return "\(priceStore.displayPrice(for: productID))/week"
    }

    private var annualDiscountBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .black))

            Text("BEST VALUE")
                .font(.system(size: 11.5, weight: .heavy))
                .tracking(0.15)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
        }
        .foregroundStyle(Color(red: 0.29, green: 0.16, blue: 0.035))
        .frame(width: 104, height: 30)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.91, blue: 0.58),
                    Color(red: 1.00, green: 0.68, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.42), lineWidth: 0.8))
        .shadow(color: Color.orange.opacity(0.28), radius: 5, y: 2)
    }

    private var continueButton: some View {
        Button(action: beginPurchase) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.56, blue: 0.0), Color(red: 1.0, green: 0.22, blue: 0.17)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                continueButtonShimmer

                Text(isPurchasing ? "Connecting..." : "Continue with \(tier.title)")
                    .font(.system(size: 18.5, weight: .bold))
                    .foregroundStyle(.white)

                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.trailing, 23)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(red: 0.36, green: 0.36, blue: 0.36), lineWidth: 2.2)
            )
        }
        .buttonStyle(TemplatePressStyle())
        .disabled(isPurchasing || isRestoring)
        .accessibilityIdentifier("membership-continue")
        .accessibilityValue(billing.productIdentifier(for: tier, isLoggedIn: usesLoggedInPaywall).rawValue)
    }

    private var continueButtonShimmer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { proxy in
                let cycleDuration = 2.2
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let progress = elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
                let travelDistance = proxy.size.width + 180
                let xPosition = -90 + (travelDistance * CGFloat(progress))

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.white.opacity(0.06), location: 0.24),
                        .init(color: Color.white.opacity(0.48), location: 0.44),
                        .init(color: Color.white.opacity(0.82), location: 0.50),
                        .init(color: Color.white.opacity(0.48), location: 0.56),
                        .init(color: Color.white.opacity(0.06), location: 0.76),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 82, height: proxy.size.height * 2.2)
                .rotationEffect(.degrees(24))
                .position(x: xPosition, y: proxy.size.height / 2)
                .blur(radius: 0.8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var footerLinks: some View {
        HStack(spacing: 12) {
            LegalLinksView(
                privacyLabel: "Privacy",
                termsLabel: "Terms",
                spacing: 12,
                onOpen: { legalDocument = $0 }
            )

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 15, weight: .medium))
                Text("Cancel anytime")
            }
        }
        .font(.system(size: 14.5, weight: .regular))
        .foregroundStyle(Color(red: 0.47, green: 0.47, blue: 0.47))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .allowsTightening(true)
    }

    private func beginPurchase() {
        guard !isPurchasing,
              isUpgradeOption(tier: tier, billing: billing) else { return }

        let productID = billing.productIdentifier(for: tier, isLoggedIn: usesLoggedInPaywall)
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
                    message: "The App Store product \(productID.rawValue) is not available for this account."
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

    private func closePaywall() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

private enum DailyFreeCreditEntry: Identifiable {
    case checkIn(sortOrder: Int)
    case task(RewardTask)
    case invite(sortOrder: Int)

    var id: String {
        switch self {
        case .checkIn: "daily-check-in"
        case .task(let task): "task-\(task.id)"
        case .invite: "invite-friends"
        }
    }

    var sortOrder: Int {
        switch self {
        case .checkIn(let sortOrder), .invite(let sortOrder): sortOrder
        case .task(let task): task.sortOrder
        }
    }
}

enum RewardCenterSpecialOfferDestination: Equatable {
    case membership
    case creditStore
    case hidden

    static func resolve(
        isSubscribed: Bool,
        isActive: Bool,
        hasMembershipOffer: Bool
    ) -> Self {
        guard isActive else { return .hidden }
        if isSubscribed { return .creditStore }
        return hasMembershipOffer ? .membership : .hidden
    }
}

private extension RewardTask {
    var isShareCreation: Bool {
        taskCode == "share_creation"
    }
}

struct CreditCenterView: View {
    @Binding var credits: Int
    @ObservedObject var accountStore: AppAccountStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.homeSubscriptionCouponOffer) private var homeSubscriptionCouponOffer
    @AppStorage("isSubscribed") private var isSubscribed = false
    @State private var showCheckInSuccess = false
    @State private var showMembership = false
    @State private var showCreditStore = false
    @State private var presentedSubscriptionOffer: CMSCouponOffer?
    @State private var isCheckingIn = false
    @State private var claimingTaskID: String?
    @State private var preparingShareTaskID: String?
    @State private var rewardShareRequest: RewardShareRequest?
    @State private var preparedShareFileURL: URL?
    @State private var grantedCredits = 0
    @State private var rewardError: String?

    init(credits: Binding<Int>, accountStore: AppAccountStore? = nil) {
        _credits = credits
        self.accountStore = accountStore ?? .shared
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RewardsBackground()

                VStack(spacing: 0) {
                    rewardsHeader

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if shouldShowRewardLoadFailure {
                                rewardLoadFailureBanner
                                    .padding(.bottom, 18)
                            }

                            ForEach(Array(orderedRewardGroups.enumerated()), id: \.element.id) { index, group in
                                rewardGroup(group, isFirst: index == 0)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 21)
                        .padding(.bottom, 48)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .background(RewardsPalette.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                if showCheckInSuccess {
                    checkInSuccessOverlay
                        .transition(.opacity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(AppPalette.accent)
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showMembership) {
            PaywallOfferFlowView()
        }
        .fullScreenCover(isPresented: $showCreditStore) {
            CreditStoreView(
                onClose: { showCreditStore = false },
                onPurchased: { _ in
                    Task {
                        await accountStore.refreshCredits()
                        credits = accountStore.creditsBalance
                    }
                }
            )
        }
        .fullScreenCover(item: $presentedSubscriptionOffer) { offer in
            SummerSalePaywallView(offer: offer)
        }
        .sheet(item: $rewardShareRequest, onDismiss: cleanupPreparedShareFile) { request in
            RewardActivityView(activityItems: [request.fileURL]) { activityType, completed, error in
                Task { @MainActor in
                    rewardShareRequest = nil

                    if let error {
                        rewardError = error.userFacingEnglishMessage()
                    } else if RewardShareSelectionPolicy.shouldClaim(
                        activityType: activityType,
                        completed: completed
                    ) {
                        claimSharedCreation(
                            task: request.rewardTask,
                            creationTaskID: request.creationTaskID,
                            activityType: activityType
                        )
                    }
                }
            }
        }
        .task {
            await accountStore.prepareRewardSessionIfNeeded()
            await accountStore.refreshCredits()
            await accountStore.refreshRewards()
        }
        .alert("Reward unavailable", isPresented: Binding(
            get: { rewardError != nil },
            set: { if !$0 { rewardError = nil } }
        )) {
            Button("OK", role: .cancel) { rewardError = nil }
        } message: {
            Text(rewardError ?? "Please try again.")
        }
    }

    private var rewardsHeader: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(RewardsPalette.ink)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.56), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.82), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close rewards")

            Spacer(minLength: 8)

            Button {
                showMembership = true
            } label: {
                RewardsStatusPill(credits: credits)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(credits) credits")
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.bottom, 23)
    }

    private var shouldShowRewardLoadFailure: Bool {
        accountStore.checkInStatus == nil
            && accountStore.lastErrorMessage != nil
            && !accountStore.isLoadingRewards
    }

    private var rewardLoadFailureBanner: some View {
        Button {
            Task {
                await accountStore.prepareRewardSessionIfNeeded()
                await accountStore.refreshCredits()
                await accountStore.refreshRewards()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))

                Text("Unable to load rewards. Tap to retry.")
                    .font(.system(size: 14, weight: .semibold))

                Spacer(minLength: 0)
            }
            .foregroundStyle(RewardsPalette.red)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(TemplatePressStyle())
        .accessibilityIdentifier("rewards-retry")
    }

    private var orderedRewardGroups: [RewardCenterGroup] {
        let groups = accountStore.rewardGroups.isEmpty ? RewardCenterGroup.defaults : accountStore.rewardGroups
        return groups.filter { group in
            guard group.isActive ?? true else { return false }
            return group.key != .specialOffer || specialOfferDestination != .hidden
        }.sorted {
            if $0.sortOrder == $1.sortOrder { return $0.key.rawValue < $1.key.rawValue }
            return $0.sortOrder < $1.sortOrder
        }
    }

    private var specialOfferDestination: RewardCenterSpecialOfferDestination {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-forceSubscriberRewardsOffer") {
            return .creditStore
        }
#endif
        return .resolve(
            isSubscribed: isSubscribed,
            isActive: accountStore.specialOfferConfig.isActive,
            hasMembershipOffer: homeSubscriptionCouponOffer != nil
        )
    }

    private var dailyFreeCreditEntries: [DailyFreeCreditEntry] {
        var entries = tasks(in: .dailyFreeCredits).map(DailyFreeCreditEntry.task)
        if accountStore.checkInStatus?.isActive ?? true {
            entries.append(.checkIn(sortOrder: accountStore.checkInStatus?.sortOrder ?? 10))
        }
        if accountStore.referralStatus?.isActive ?? false {
            entries.append(.invite(sortOrder: accountStore.referralStatus?.sortOrder ?? 30))
        }
        return entries.sorted {
            if $0.sortOrder == $1.sortOrder { return $0.id < $1.id }
            return $0.sortOrder < $1.sortOrder
        }
    }

    private func tasks(in group: RewardCenterGroupKey) -> [RewardTask] {
        accountStore.rewardTasks
            .filter { task in
                guard task.taskCode != SubscriberScratchCampaign.rewardTaskCode else {
                    return false
                }
                let fallback: RewardCenterGroupKey = task.taskCode == "share_creation"
                    ? .dailyFreeCredits
                    : .oneTimeRewards
                return (task.rewardCenterGroup ?? fallback) == group
            }
            .sorted {
                if $0.sortOrder == $1.sortOrder { return $0.taskCode < $1.taskCode }
                return $0.sortOrder < $1.sortOrder
            }
    }

    @ViewBuilder
    private func rewardGroup(_ group: RewardCenterGroup, isFirst: Bool) -> some View {
        sectionTitle(group.displayTitle)
            .padding(.top, isFirst ? 0 : 30)

        switch group.key {
        case .dailyFreeCredits:
            if accountStore.checkInStatus?.isActive ?? true {
                Text("up to \(accountStore.checkInStatus?.rewards.reduce(0) { $0 + $1.credits } ?? 0) per week")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(RewardsPalette.muted)
                    .padding(.top, 6)
            }
            ForEach(dailyFreeCreditEntries) { entry in
                dailyFreeCreditRow(entry)
                    .padding(.top, 10)
            }

        case .specialOffer:
            switch specialOfferDestination {
            case .membership:
                if let offer = homeSubscriptionCouponOffer {
                    RewardsActionRow(
                        title: "Special Membership Offer",
                        creditAmount: 400,
                        icon: .asset("RewardsGiftIcon", size: 42),
                        actionTitle: "Get",
                        enabled: true,
                        highlightOffer: true
                    ) {
                        presentedSubscriptionOffer = offer
                    }
                    .padding(.top, 10)
                }
            case .creditStore:
                RewardsCreditStoreBanner {
                    showCreditStore = true
                }
                .padding(.top, 10)
            case .hidden:
                EmptyView()
            }

        case .oneTimeRewards:
            ForEach(tasks(in: .oneTimeRewards)) { task in
                rewardTaskRow(task)
                    .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private func dailyFreeCreditRow(_ entry: DailyFreeCreditEntry) -> some View {
        switch entry {
        case .checkIn:
            dailyCheckInCard
        case .task(let task):
            rewardTaskRow(task)
        case .invite:
            NavigationLink {
                InviteFriendsView(credits: $credits, accountStore: accountStore)
            } label: {
                RewardsInviteBanner(
                    creditAmount: accountStore.referralStatus?.rewardConfig?.signupReferrerCredits ?? 0
                )
            }
            .buttonStyle(TemplatePressStyle())
            .accessibilityIdentifier("invite-friends-link")
        }
    }

    private func rewardTaskRow(_ task: RewardTask) -> some View {
        RewardsActionRow(
            title: task.displayTitle,
            creditAmount: task.rewardCredits,
            icon: rewardIcon(for: task.taskCode),
            actionTitle: rewardActionTitle(for: task),
            enabled: canStart(task),
            actionColor: RewardsPalette.red,
            creditStatusText: task.isClaimed && task.isShareCreation
                ? "\(task.rewardCredits) claimed today"
                : nil
        ) {
            claim(task)
        }
    }

    private var dailyCheckInCard: some View {
        VStack(spacing: 13) {
            HStack(spacing: 7) {
                ForEach(accountStore.checkInStatus?.rewards ?? []) { reward in
                    let isHighlighted = reward.status == "claimable"
                    let isClaimed = reward.status == "signed" || reward.status == "signed_today"

                    VStack(spacing: 6) {
                        Text("Day\(reward.day)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(
                                isHighlighted
                                    ? Color.white
                                    : isClaimed
                                        ? RewardsPalette.orange.opacity(0.36)
                                        : RewardsPalette.muted
                            )

                        Group {
                            if isClaimed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color(red: 1.00, green: 0.76, blue: 0.35), in: Circle())
                            } else {
                                Image("RewardsCreditToken")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .frame(height: 24)

                        Text("+\(reward.credits)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(
                                isHighlighted
                                    ? Color.white
                                    : isClaimed
                                        ? RewardsPalette.orange.opacity(0.36)
                                        : RewardsPalette.orange
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .background(
                        isHighlighted
                            ? RewardsPalette.selectedDay
                            : isClaimed
                                ? RewardsPalette.claimedDay
                                : RewardsPalette.card,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                isHighlighted
                                    ? RewardsPalette.orange
                                    : RewardsPalette.orange.opacity(isClaimed ? 0.08 : 0.14),
                                lineWidth: isHighlighted ? 1.2 : 1
                            )
                    )
                }
            }

            Button {
                guard canCheckIn else { return }
                isCheckingIn = true
                Task {
                    defer { isCheckingIn = false }
                    do {
                        let result = try await accountStore.checkIn()
                        credits = accountStore.creditsBalance
                        grantedCredits = result.creditsGranted
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCheckInSuccess = true
                        }
                    } catch {
                        rewardError = error.userFacingEnglishMessage()
                    }
                }
            } label: {
                Text(checkInButtonTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 250, height: 44)
                    .background(
                        !canCheckIn
                            ? AnyShapeStyle(RewardsPalette.muted.opacity(0.55))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [RewardsPalette.orange, RewardsPalette.red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            ),
                        in: Capsule()
                    )
            }
            .buttonStyle(TemplatePressStyle())
            .disabled(!canCheckIn)
            .accessibilityIdentifier("daily-check-in")
        }
        .padding(.horizontal, 11)
        .padding(.top, 20)
        .padding(.bottom, 13)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var checkInSuccessOverlay: some View {
        ZStack {
            Color.black.opacity(0.56)
                .ignoresSafeArea()
                .onTapGesture {
                    showCheckInSuccess = false
                }

            Button {
                showCheckInSuccess = false
            } label: {
                VStack(spacing: 22) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(.green)
                    Text("Check-in successful!")
                        .font(.title3.bold())
                        .foregroundStyle(AppPalette.brownInk)
                    Text("+\(grantedCredits) credits")
                        .font(.headline)
                        .foregroundStyle(AppPalette.orange)
                }
                .frame(maxWidth: 310)
                .frame(height: 230)
                .background(AppPalette.backgroundTop, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppPalette.surfaceEdge.opacity(0.72), lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss check-in success")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(RewardsPalette.brown)
    }

    private var canCheckIn: Bool {
        guard let status = accountStore.checkInStatus else { return false }
        return status.isActive && !status.signedToday && status.claimableDay != nil && !isCheckingIn
    }

    private var checkInButtonTitle: String {
        guard let status = accountStore.checkInStatus else { return "Loading..." }
        if !status.isActive { return "Unavailable" }
        if status.signedToday { return "Come Tomorrow" }
        return isCheckingIn ? "Checking In..." : "Check In"
    }

    private func canClaim(_ task: RewardTask) -> Bool {
        !task.isClaimed && canStart(task)
    }

    private func canStart(_ task: RewardTask) -> Bool {
        guard !task.requiresServerVerification,
              claimingTaskID == nil,
              preparingShareTaskID == nil else { return false }
        return task.isShareCreation || !task.isClaimed
    }

    private func rewardActionTitle(for task: RewardTask) -> String {
        if preparingShareTaskID == task.id { return "Preparing" }
        if claimingTaskID == task.id { return "Claiming" }
        if task.isShareCreation { return "Share" }
        if task.isClaimed { return "Claimed" }
        if task.requiresServerVerification { return "Pending" }
        return "Start"
    }

    private func rewardIcon(for code: String) -> RewardsActionIcon {
        switch code {
        case let value where value.contains("share"):
            .asset("RewardsShareIcon", size: 42)
        case let value where value.contains("notification"):
            .asset("RewardsBellIcon", size: 42)
        case let value where value.contains("tiktok"):
            .asset("RewardsTikTokIcon", size: 42)
        case let value where value.contains("instagram"):
            .instagram
        case "follow_x", "follow_twitter":
            .x
        default:
            .asset("RewardsCreditToken", size: 32)
        }
    }

    private func claim(_ task: RewardTask) {
        guard canStart(task) else { return }
        if task.isShareCreation {
            prepareCreationShare(task)
            return
        }
        guard canClaim(task) else { return }
        if task.taskCode == "enable_notifications" {
            enableNotificationsAndClaim(task)
            return
        }

        claimingTaskID = task.id
        Task {
            defer { claimingTaskID = nil }
            do {
                _ = try await accountStore.claimRewardTask(task)
                credits = accountStore.creditsBalance
            } catch {
                rewardError = error.userFacingEnglishMessage()
            }
        }
    }

    private func prepareCreationShare(_ task: RewardTask) {
        preparingShareTaskID = task.id
        rewardError = nil

        Task {
            defer { preparingShareTaskID = nil }

            if accountStore.historyTasks.isEmpty {
                await accountStore.refreshHistory()
            }

            guard let creation = accountStore.historyTasks.first(where: {
                $0.status == "completed" && $0.resultURL != nil
            }) else {
                rewardError = "Create a photo or video first, then come back to share it."
                return
            }

            do {
                let fileURL = try await RewardShareAssetPreparer.download(creation)
                preparedShareFileURL = fileURL
                rewardShareRequest = RewardShareRequest(
                    rewardTask: task,
                    creationTaskID: creation.id,
                    fileURL: fileURL
                )
            } catch {
                rewardError = error.userFacingEnglishMessage()
            }
        }
    }

    private func claimSharedCreation(
        task: RewardTask,
        creationTaskID: String,
        activityType: UIActivity.ActivityType?
    ) {
        guard !task.isClaimed, claimingTaskID == nil else { return }
        claimingTaskID = task.id

        Task {
            defer { claimingTaskID = nil }
            do {
                _ = try await accountStore.claimRewardTask(
                    task,
                    evidence: [
                        "source": "ios_reward_center",
                        "share_completed": "true",
                        "activity_type": activityType?.rawValue ?? "unknown",
                        "creation_task_id": creationTaskID,
                    ]
                )
                credits = accountStore.creditsBalance
            } catch {
                rewardError = error.userFacingEnglishMessage()
            }
        }
    }

    private func cleanupPreparedShareFile() {
        guard let preparedShareFileURL else { return }
        try? FileManager.default.removeItem(at: preparedShareFileURL)
        self.preparedShareFileURL = nil
    }

    private func enableNotificationsAndClaim(_ task: RewardTask) {
        claimingTaskID = task.id
        rewardError = nil

        Task {
            defer { claimingTaskID = nil }
            do {
                let notificationCenter = UNUserNotificationCenter.current()
                var settings = await notificationCenter.notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    _ = try await notificationCenter.requestAuthorization(
                        options: [.alert, .badge, .sound]
                    )
                    settings = await notificationCenter.notificationSettings()
                }

                guard let authorizationStatus = notificationRewardEvidence(
                    for: settings.authorizationStatus
                ) else {
                    rewardError = "Please enable notifications in iOS Settings, then tap Start again."
                    return
                }

                UIApplication.shared.registerForRemoteNotifications()
                _ = try await accountStore.claimRewardTask(
                    task,
                    evidence: [
                        "source": "ios_app",
                        "notification_authorization_status": authorizationStatus,
                        "notification_checked_at": ISO8601DateFormatter().string(from: Date()),
                    ]
                )
                credits = accountStore.creditsBalance
            } catch {
                rewardError = error.userFacingEnglishMessage()
            }
        }
    }

    private func notificationRewardEvidence(
        for status: UNAuthorizationStatus
    ) -> String? {
        switch status {
        case .authorized:
            "authorized"
        case .provisional:
            "provisional"
        case .ephemeral:
            "ephemeral"
        case .denied, .notDetermined:
            nil
        @unknown default:
            nil
        }
    }
}

private struct RewardShareRequest: Identifiable {
    let id = UUID()
    let rewardTask: RewardTask
    let creationTaskID: String
    let fileURL: URL
}

enum RewardShareSelectionPolicy {
    /// This reward is intentionally low-friction: choosing any activity is
    /// sufficient, even if that activity later reports that it was cancelled.
    static func shouldClaim(
        activityType: UIActivity.ActivityType?,
        completed: Bool
    ) -> Bool {
        completed || activityType != nil
    }
}

private struct RewardActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: (UIActivity.ActivityType?, Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { activityType, completed, _, error in
            completion(activityType, completed, error)
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

private enum RewardShareAssetPreparer {
    static func download(_ creation: GenerationHistoryTask) async throws -> URL {
        guard let sourceURL = creation.resultURL else {
            throw RewardShareAssetError.missingCreation
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw RewardShareAssetError.downloadFailed
        }

        let fileExtension = preferredExtension(
            sourceURL: sourceURL,
            response: response,
            isVideo: creation.isVideo
        )
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Photo-Revival-Creation-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw RewardShareAssetError.couldNotPrepare(error)
        }
    }

    private static func preferredExtension(
        sourceURL: URL,
        response: URLResponse,
        isVideo: Bool
    ) -> String {
        let candidates = [
            response.suggestedFilename.map { URL(fileURLWithPath: $0).pathExtension },
            Optional(sourceURL.pathExtension),
        ]

        if let candidate = candidates.compactMap({ $0 }).first(where: isSafeFileExtension) {
            return candidate.lowercased()
        }
        return isVideo ? "mp4" : "jpg"
    }

    nonisolated private static func isSafeFileExtension(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 8
            && value.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
    }
}

private enum RewardShareAssetError: LocalizedError {
    case missingCreation
    case downloadFailed
    case couldNotPrepare(Error)

    var errorDescription: String? {
        switch self {
        case .missingCreation:
            "This creation is no longer available. Please create a new one and try again."
        case .downloadFailed:
            "We couldn't download this creation for sharing. Please try again."
        case .couldNotPrepare:
            "We couldn't prepare this creation for sharing. Please try again."
        }
    }
}

private enum RewardsPalette {
    static let ink = Color(red: 0.08, green: 0.07, blue: 0.05)
    static let brown = Color(red: 0.68, green: 0.42, blue: 0.19)
    static let muted = Color(red: 0.55, green: 0.55, blue: 0.55)
    static let orange = Color(red: 1.00, green: 0.60, blue: 0.14)
    static let red = Color(red: 1.00, green: 0.23, blue: 0.16)
    static let panel = Color(red: 0.992, green: 0.965, blue: 0.914)
    static let card = Color.white.opacity(0.74)
    static let selectedDay = Color(red: 1.00, green: 0.68, blue: 0.30)
    static let claimedDay = Color(red: 1.00, green: 0.91, blue: 0.72)
}

private struct RewardsBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.85, green: 0.76, blue: 0.59), Color(red: 0.89, green: 0.82, blue: 0.70), RewardsPalette.panel],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 82, height: 82)
                .position(x: 42, y: 16)
            Circle()
                .fill(.white.opacity(0.13))
                .frame(width: 110, height: 110)
                .position(x: 174, y: 34)
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 96, height: 96)
                .position(x: 390, y: 83)

            ForEach([CGPoint(x: 102, y: 30), CGPoint(x: 146, y: 92), CGPoint(x: 210, y: 58)], id: \.self) { point in
                Image(systemName: "sparkle")
                    .font(.system(size: 22, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.70))
                    .position(point)
            }
        }
        .ignoresSafeArea()
    }
}

private struct RewardsStatusPill: View {
    let credits: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("PRO")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color(red: 0.91, green: 0.21, blue: 0.16), in: Capsule())

            Image("RewardsCreditToken")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text("\(credits)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RewardsPalette.muted)
                .frame(minWidth: 16, alignment: .leading)
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(RewardsPalette.red)
                .frame(width: 24, height: 24)
                .background(.white, in: Circle())
        }
        .padding(.horizontal, 3)
        .frame(height: 38)
        .background(.white.opacity(0.48), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.76), lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
    }
}

private enum RewardsActionIcon {
    case asset(String, size: CGFloat)
    case instagram
    case x
}

private struct RewardsActionIconView: View {
    let icon: RewardsActionIcon

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 1.00, green: 0.97, blue: 0.89))

            switch icon {
            case .asset(let name, let size):
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            case .instagram:
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple, Color.pink, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            case .x:
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text("X")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 44, height: 44)
    }
}

private struct RewardsActionRow: View {
    let title: String
    let creditAmount: Int
    let icon: RewardsActionIcon
    let actionTitle: String
    let enabled: Bool
    var highlightOffer = false
    var actionColor = RewardsPalette.orange
    var creditStatusText: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            if enabled { action() }
        } label: {
            HStack(spacing: 14) {
                RewardsActionIconView(icon: icon)

                VStack(alignment: .leading, spacing: 3) {
                    if highlightOffer {
                        Text(title)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(RewardsPalette.ink)
                    } else {
                        Text(title)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(RewardsPalette.ink)
                    }

                    if let creditStatusText {
                        Label(creditStatusText, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(RewardsPalette.orange)
                    } else {
                        HStack(spacing: 7) {
                            Image("RewardsCreditToken")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 21, height: 21)
                            Text(highlightOffer ? "400/week" : "\(creditAmount)")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(RewardsPalette.orange)
                        }
                    }
                }

                Spacer(minLength: 4)

                Text(actionTitle)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(enabled ? .white : RewardsPalette.muted.opacity(0.60))
                    .frame(width: 82, height: 38)
                    .background(enabled ? actionColor : Color(red: 1.00, green: 0.95, blue: 0.85), in: Capsule())
            }
            .padding(.horizontal, 15)
            .frame(height: 62)
            .background(.white.opacity(0.87), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct RewardsCreditStoreBanner: View {
    let action: () -> Void

    private var creditPackSummary: String {
        CreditProductCatalog.packs.map(\.creditsLabel).joined(separator: " · ") + " credits"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.92))
                        .frame(width: 54, height: 54)
                        .shadow(color: RewardsPalette.orange.opacity(0.18), radius: 8, y: 3)

                    Image("RewardsCreditToken")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)

                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 22, y: -21)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text("Top Up Credits")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(RewardsPalette.ink)

                        Text("MEMBER")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.5)
                            .foregroundStyle(Color(red: 0.55, green: 0.27, blue: 0.04))
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background(.white.opacity(0.78), in: Capsule())
                    }

                    Text(creditPackSummary)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RewardsPalette.brown)

                    Text("One-time packs · Never expire")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RewardsPalette.muted)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.76)

                Spacer(minLength: 2)

                HStack(spacing: 3) {
                    Text("Shop")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background(RewardsPalette.red, in: Capsule())
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 86)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.94),
                        Color(red: 1.00, green: 0.91, blue: 0.70).opacity(0.90),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(RewardsPalette.orange.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(TemplatePressStyle())
        .accessibilityLabel("Buy credit packs")
        .accessibilityHint("Opens one-time credit packs")
        .accessibilityIdentifier("rewards-credit-store-entry")
    }
}

private struct RewardsInviteBanner: View {
    let creditAmount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image("RewardsInviteArtwork")
                .resizable()
                .scaledToFill()
                .frame(width: 82, height: 80)
                .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text("Invite Friends")
                    .font(.system(size: 17, weight: .bold))
                Text("Get More Rewards")
                    .font(.system(size: 13, weight: .regular))
                HStack(spacing: 6) {
                    Image("RewardsCreditToken")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text("\(creditAmount)")
                        .font(.system(size: 15, weight: .regular))
                }
            }
            .foregroundStyle(.white)

            Spacer(minLength: 5)

            Text("Invite")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(RewardsPalette.orange)
                .frame(width: 82, height: 38)
                .background(.white, in: Capsule())
        }
        .padding(.trailing, 14)
        .frame(height: 80)
        .background(
            LinearGradient(
                colors: [Color(red: 1.00, green: 0.34, blue: 0.34), Color(red: 1.00, green: 0.74, blue: 0.20)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct InviteFriendsView: View {
    @Binding var credits: Int
    @ObservedObject var accountStore: AppAccountStore

    @State private var redemptionCode = ""
    @State private var showInfo = false
    @State private var showCopied = false
    @State private var showRedeemed = false
    @State private var isRedeeming = false
    @State private var redemptionMessage = ""

    init(credits: Binding<Int>, accountStore: AppAccountStore? = nil) {
        _credits = credits
        self.accountStore = accountStore ?? .shared
    }

    private var invitationCode: String {
        accountStore.referralStatus?.invitationCode ?? "Loading..."
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppPalette.backgroundTop, Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Get More Rewards")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppPalette.brownInk)
                        Text("Create endless possibilities with friends")
                            .font(.headline)
                            .foregroundStyle(AppPalette.brownInk)
                    }

                    invitationSteps

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Invite Friends to Earn Credits", systemImage: "diamond.fill")
                            .font(.title3.bold())
                            .foregroundStyle(AppPalette.brownInk)

                        HStack {
                            Text(invitationCode)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppPalette.surfaceEdge)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = invitationCode
                                showCopied = true
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.title3)
                            }
                            .accessibilityLabel("Copy invitation code")
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 58)
                        .background(AppPalette.backgroundTop, in: RoundedRectangle(cornerRadius: 10))

                        if let code = accountStore.referralStatus?.invitationCode {
                            ShareLink(item: "Join me on Photo Revival. After signing in, open Invite Friends and redeem invitation code \(code).") {
                                Label("Invite Now", systemImage: "arrow.right")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                                    .background(AppPalette.orange, in: Capsule())
                            }
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Reward Redemption", systemImage: "gift.fill")
                            .font(.title3.bold())
                            .foregroundStyle(AppPalette.brownInk)

                        HStack(spacing: 10) {
                            TextField("Invitation Code", text: $redemptionCode)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Button(isRedeeming ? "Redeeming..." : "Redeem") {
                                redeemInvitationCode()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                redemptionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || isRedeeming
                                    || accountStore.referralStatus?.hasRedeemedReferral == true
                            )
                        }
                        .padding(12)
                        .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(18)
                    .background(AppPalette.backgroundTop.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Invite Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Invitation information")
            }
        }
        .task {
            await accountStore.refreshRewards()
        }
        .alert("Invitation rewards", isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(referralInformationText)
        }
        .alert("Copied", isPresented: $showCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The invitation code is on your clipboard.")
        }
        .alert("Invitation code", isPresented: $showRedeemed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(redemptionMessage)
        }
    }

    private var invitationSteps: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                invitationStep("Share code", systemImage: "person.badge.plus")
                Image(systemName: "chevron.right.2")
                    .foregroundStyle(AppPalette.orange)
                invitationStep("Friend redeems", systemImage: "person.crop.circle.badge.checkmark")
                Image(systemName: "chevron.right.2")
                    .foregroundStyle(AppPalette.orange)
                invitationStep("Earn rewards", systemImage: "gift.fill")
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(signupRewardText, systemImage: "diamond.fill")
                Label(subscriptionRewardText, systemImage: "diamond.fill")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppPalette.brownInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppPalette.backgroundTop.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(18)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 12))
    }

    private func invitationStep(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(AppPalette.orange)
            Text(title)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppPalette.ink)
        }
        .frame(maxWidth: .infinity)
    }

    private var signupRewardText: String {
        let config = accountStore.referralStatus?.rewardConfig
        return "You earn \(config?.signupReferrerCredits ?? 0) credits and your friend earns \(config?.signupReferredCredits ?? 0) when they redeem your invitation code"
    }

    private var subscriptionRewardText: String {
        let amount = accountStore.referralStatus?.rewardConfig?.subscriptionReferrerCredits ?? 0
        return "You earn an additional \(amount) credits when your invited friend starts a qualifying subscription"
    }

    private var referralInformationText: String {
        "\(signupRewardText). \(subscriptionRewardText). Rewards are issued by the server and cannot be claimed twice."
    }

    private func redeemInvitationCode() {
        let code = redemptionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !isRedeeming else { return }
        isRedeeming = true
        Task {
            defer { isRedeeming = false }
            do {
                let result = try await accountStore.redeemReferral(code: code)
                credits = accountStore.creditsBalance
                redemptionCode = ""
                let amount = result.referredRewardCredits ?? result.signupRewardCredits ?? 0
                redemptionMessage = result.redeemed
                    ? "Invitation accepted. \(amount) credits were added by the server."
                    : "This invitation was already redeemed. No duplicate credits were issued."
            } catch {
                redemptionMessage = error.userFacingEnglishMessage()
            }
            showRedeemed = true
        }
    }
}

struct SuggestionView: View {
    @Environment(\.dismiss) private var dismiss
    private let api = PhotoReviveAPIClient.shared
    @State private var suggestion = ""
    @State private var email = ""
    @State private var selectedScreenshot: PhotosPickerItem?
    @State private var screenshotImage: UIImage?
    @State private var showFAQ = false
    @State private var showSubmitted = false
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var didPrefillEmail = false

    private var canSubmit: Bool {
        !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperTextureBackground()

                Form {
                    Section {
                        Text("Suggest your favorite video or photo template - we're listening!")
                            .font(.headline)
                            .listRowBackground(Color.clear)
                    }

                    Section("Your Suggestion") {
                        TextEditor(text: $suggestion)
                            .frame(minHeight: 180)
                            .overlay(alignment: .topLeading) {
                                if suggestion.isEmpty {
                                    Text("Please enter your suggestion (up to 1000 characters)")
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    Section("Your Email") {
                        HStack(spacing: 8) {
                            TextField(
                                "",
                                text: $email,
                                prompt: Text("name@example.com").foregroundStyle(.tertiary)
                            )
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                            if !email.isEmpty {
                                Button {
                                    email = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear email")
                            }
                        }
                    }

                    Section("Screenshot") {
                        PhotosPicker(selection: $selectedScreenshot, matching: .images) {
                            HStack(spacing: 14) {
                                if let screenshotImage {
                                    FrostedUploadedPhoto(image: screenshotImage)
                                        .frame(width: 68, height: 68)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.title2)
                                        .foregroundStyle(AppPalette.surfaceEdge)
                                        .frame(width: 68, height: 68)
                                        .background(AppPalette.backgroundTop, in: RoundedRectangle(cornerRadius: 8))
                                }

                                Text(screenshotImage == nil ? "Add Screenshot" : "Change Screenshot")
                                    .font(.headline)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Section {
                        Button {
                            submitSuggestion()
                        } label: {
                            HStack(spacing: 10) {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isSubmitting ? "Sending…" : "Send Suggestion")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!canSubmit || isSubmitting)
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Close suggestion")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("FAQ") {
                        showFAQ = true
                    }
                }
            }
        }
        .tint(AppPalette.accent)
        .preferredColorScheme(.light)
        .onChange(of: suggestion) { _, newValue in
            if newValue.count > 1000 {
                suggestion = String(newValue.prefix(1000))
            }
        }
        .onChange(of: selectedScreenshot) { _, item in
            loadScreenshot(from: item)
        }
        .task {
            guard !didPrefillEmail else { return }
            didPrefillEmail = true
            if email.isEmpty, let accountEmail = PhotoReviveAuthClient.shared.currentUserEmail {
                email = accountEmail
            }
        }
        .alert("Suggestion FAQ", isPresented: $showFAQ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Describe the style, subject and expected result. A reference screenshot is optional but helpful.")
        }
        .alert("Suggestion sent", isPresented: $showSubmitted) {
            Button("Done") {
                dismiss()
            }
        } message: {
            Text("Thanks for helping us improve Photo Revival.")
        }
        .alert(
            "Unable to send suggestion",
            isPresented: Binding(
                get: { submissionError != nil },
                set: { if !$0 { submissionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(submissionError ?? "Please try again.")
        }
    }

    private func submitSuggestion() {
        let trimmedSuggestion = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSuggestion.isEmpty, !isSubmitting else { return }
        isSubmitting = true

        Task {
            defer { isSubmitting = false }
            do {
                let screenshotData = screenshotImage?.jpegData(compressionQuality: 0.82)
                _ = try await api.submitSuggestion(
                    content: trimmedSuggestion,
                    contactEmail: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    screenshotData: screenshotData
                )
                showSubmitted = true
            } catch {
                submissionError = error.userFacingEnglishMessage(
                    fallback: "Your request could not be sent. Please try again."
                )
            }
        }
    }

    private func loadScreenshot(from item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                screenshotImage = image
            }
        }
    }
}

private enum MembershipTier: String, CaseIterable, Identifiable {
    case pro
    case proPlus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pro: "PRO"
        case .proPlus: "PRO+"
        }
    }

    var weeklyCredits: Int { self == .pro ? 400 : 900 }
    var yearlyVideos: Int { self == .pro ? 572 : 1300 }
    var accent: Color { self == .pro ? Color.yellow : AppPalette.accent }

    var mediaStripAsset: String {
        self == .pro ? "PaywallProMediaStrip" : "PaywallProPlusMediaStrip"
    }

    var detailAccent: Color {
        self == .pro
            ? Color(red: 1.0, green: 0.34, blue: 0.15)
            : Color(red: 1.0, green: 0.20, blue: 0.23)
    }

    var tierGradient: [Color] {
        switch self {
        case .pro:
            [
                Color(red: 1.0, green: 0.78, blue: 0.18),
                Color(red: 1.0, green: 0.91, blue: 0.72),
                Color(red: 1.0, green: 0.80, blue: 0.25)
            ]
        case .proPlus:
            [
                Color(red: 1.0, green: 0.17, blue: 0.18),
                Color(red: 1.0, green: 0.45, blue: 0.47)
            ]
        }
    }

    var planAccent: Color {
        self == .pro
            ? Color(red: 0.86, green: 0.64, blue: 0.33)
            : Color(red: 0.92, green: 0.29, blue: 0.22)
    }

    var selectionAccent: Color {
        self == .pro
            ? Color(red: 1.0, green: 0.49, blue: 0.17)
            : Color(red: 1.0, green: 0.31, blue: 0.30)
    }

    var planBackground: [Color] {
        self == .pro
            ? [Color(red: 0.23, green: 0.19, blue: 0.145), Color(red: 0.23, green: 0.19, blue: 0.145)]
            : [Color(red: 0.22, green: 0.145, blue: 0.13), Color(red: 0.22, green: 0.145, blue: 0.13)]
    }

}

private enum MembershipBilling: String, CaseIterable, Identifiable {
    case annual
    case weekly

    var id: String { rawValue }
    var title: String { self == .annual ? "Annual Plan" : "Weekly Plan" }
    var loggedInTitle: String { self == .annual ? "Annual" : "Weekly" }

    func planLevel(for tier: MembershipTier) -> SubscriptionPlanLevel {
        switch (self, tier) {
        case (.weekly, .pro): .proWeekly
        case (.annual, .pro): .proAnnual
        case (.weekly, .proPlus): .proPlusWeekly
        case (.annual, .proPlus): .proPlusAnnual
        }
    }

    func productIdentifier(for tier: MembershipTier, isLoggedIn: Bool = false) -> SubscriptionProductID {
        switch (isLoggedIn, tier, self) {
        case (false, .pro, .annual): .proYearly
        case (false, .pro, .weekly): .proWeekly
        case (false, .proPlus, .annual): .proPlusYearly
        case (false, .proPlus, .weekly): .proPlusWeekly
        case (true, .pro, .annual): .loggedProYearly
        case (true, .pro, .weekly): .loggedProWeekly
        case (true, .proPlus, .annual): .loggedProPlusYearly
        case (true, .proPlus, .weekly): .loggedProPlusWeekly
        }
    }
}
