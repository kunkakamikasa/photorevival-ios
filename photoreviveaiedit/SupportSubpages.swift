import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct MembershipPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isSubscribed") private var isSubscribed = false
    @AppStorage("isLoggedIn") private var storedIsLoggedIn = false
    let onClose: (() -> Void)?
    private let isLoggedInOverride: Bool?
    @State private var tier: MembershipTier = .pro
    @State private var billing: MembershipBilling = .annual
    @State private var isPurchasing = false
    @State private var purchaseAlert: SubscriptionPurchaseAlert?

    private let designWidth: CGFloat = 430
    private let designHeight: CGFloat = 848
    private let loggedInDesignHeight: CGFloat = 932

    init(isLoggedIn: Bool? = nil, onClose: (() -> Void)? = nil) {
        self.isLoggedInOverride = isLoggedIn
        self.onClose = onClose
    }

    private var usesLoggedInPaywall: Bool {
        (isLoggedInOverride ?? storedIsLoggedIn)
            || ProcessInfo.processInfo.arguments.contains("-loggedIn")
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / designWidth
            let contentHeight = usesLoggedInPaywall ? loggedInDesignHeight : designHeight

            ZStack(alignment: .topLeading) {
                paywallBackground

                ScrollView(.vertical) {
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
                            width: proxy.size.width,
                            height: contentHeight * scale,
                            alignment: .topLeading
                        )
                }
                .scrollIndicators(.hidden)
            }
        }
        .ignoresSafeArea(edges: usesLoggedInPaywall ? .all : .bottom)
        .preferredColorScheme(.dark)
        .alert(item: $purchaseAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var paywallContent: some View {
        VStack(spacing: 0) {
            paywallHeader
                .frame(width: designWidth, height: 310)

            Color.clear.frame(height: 58)

            benefitSection
                .frame(width: designWidth, height: 170, alignment: .top)

            Color.clear.frame(height: 38)

            membershipPlanRow(.annual)
                .frame(width: 390, height: 64)

            Color.clear.frame(height: 14)

            membershipPlanRow(.weekly)
                .frame(width: 390, height: 70)

            Color.clear.frame(height: 33)

            continueButton
                .frame(width: 390, height: 47)

            Color.clear.frame(height: 20)

            footerLinks
                .frame(width: 390, height: 22)
        }
    }

    private var loggedInPaywallContent: some View {
        ZStack(alignment: .top) {
            loggedInHero

            VStack(spacing: 0) {
                Color.clear.frame(height: 299)

                loggedInTierHeadings
                    .frame(width: designWidth, height: 52)

                loggedInBenefitCards
                    .frame(width: designWidth, height: 190)

                Color.clear.frame(height: 30)

                loggedInMembershipPlanRow(.annual)
                    .frame(width: 390, height: 82)

                Color.clear.frame(height: 12)

                loggedInMembershipPlanRow(.weekly)
                    .frame(width: 390, height: 82)

                Color.clear.frame(height: 17)

                loggedInRefundGuarantee
                    .frame(width: 390, height: 24)

                Color.clear.frame(height: 17)

                loggedInContinueButton
                    .frame(width: 390, height: 64)

                Color.clear.frame(height: 13)

                footerLinks
                    .frame(width: 390, height: 22)
            }
        }
        .frame(width: designWidth, height: loggedInDesignHeight, alignment: .top)
    }

    private var loggedInHero: some View {
        ZStack(alignment: .top) {
            Image(tier.loggedInHeroAsset)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: designWidth, height: 382)
                .clipped()
                .animation(.easeInOut(duration: 0.22), value: tier)

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

            Button(action: showInformationAlert) {
                Text("Restore")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 82, height: 36)
                    .background(.black.opacity(0.24), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.78), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .position(x: 370, y: 76)
            .accessibilityLabel("Restore")
        }
        .frame(width: designWidth, height: 382)
        .clipped()
    }

    private var loggedInTierOffset: CGFloat {
        tier == .pro ? 18 : -282
    }

    private var loggedInTierHeadings: some View {
        HStack(spacing: 12) {
            ForEach(MembershipTier.allCases) { option in
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
                    .background(.ultraThinMaterial, in: Capsule())

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 1)
                .frame(width: 315, height: 52)
            }
        }
        .offset(x: loggedInTierOffset)
        .frame(width: designWidth, alignment: .leading)
        .clipped()
        .animation(.easeInOut(duration: 0.22), value: tier)
    }

    private var loggedInBenefitCards: some View {
        HStack(spacing: 12) {
            ForEach(MembershipTier.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        tier = option
                    }
                } label: {
                    loggedInBenefitCard(option)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(tier == option ? .isSelected : [])
                .accessibilityIdentifier("membership-tier-\(option.rawValue)")
            }
        }
        .offset(x: loggedInTierOffset)
        .frame(width: designWidth, alignment: .leading)
        .clipped()
        .animation(.easeInOut(duration: 0.22), value: tier)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > 34 else { return }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        tier = value.translation.width < 0 ? .proPlus : .pro
                    }
                }
        )
    }

    private func loggedInBenefitCard(_ option: MembershipTier) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Up to \(option.yearlyVideos) videos yearly")
                .font(.system(size: 16.5, weight: .regular))
                .foregroundStyle(.white)
                .padding(.bottom, 14)

            loggedInBenefitRow("Priority & ", emphasis: "800+", suffix: " Style", tier: option)
            loggedInBenefitRow("Ad-free & No Watermark", tier: option)
            loggedInBenefitRow("", emphasis: "\(option.creditDiscount)%", suffix: " OFF Lifetime Credits", tier: option)
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
        Button {
            billing = option
        } label: {
            HStack(spacing: 13) {
                planSelectionIndicator(isSelected: billing == option)

                VStack(alignment: .leading, spacing: option == .annual ? 4 : 0) {
                    Text(option.loggedInTitle)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)

                    if option == .annual {
                        Text(option.loggedInAnnualPrice(for: tier))
                            .font(.system(size: 18.5, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }

                Spacer(minLength: 8)

                Text(option.loggedInTrailingPrice(for: tier))
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
                        .offset(x: 5, y: -17)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.loggedInTitle), \(option.loggedInTrailingPrice(for: tier))")
        .accessibilityValue(option.productIdentifier(for: tier, isLoggedIn: true).rawValue)
        .accessibilityAddTraits(billing == option ? .isSelected : [])
        .accessibilityIdentifier("membership-billing-\(option.rawValue)")
    }

    private var loggedInRefundGuarantee: some View {
        HStack(spacing: 6) {
            Text("100% Refund Guarantee")
            Image(systemName: "apple.logo")
                .font(.system(size: 16, weight: .medium))
            Text("Secured By Apple")
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
        .disabled(isPurchasing)
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
            Image(tier.mediaStripAsset)
                .resizable()
                .interpolation(.high)
                .frame(width: designWidth, height: 310)

            Button(action: closePaywall) {
                Color.clear
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(x: 37, y: 30)
            .accessibilityLabel("Close membership")

            Button {
                showInformationAlert()
            } label: {
                Color.clear
                    .frame(width: 98, height: 48)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .position(x: 370, y: 30)
            .accessibilityLabel("Restore")
        }
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
            VStack(alignment: .leading, spacing: 6) {
                benefitRow(priorityBenefitText)
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
        .padding(.top, 41)
        .padding(.bottom, 13)
        .frame(width: 390, height: 148)
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

    private var priorityBenefitText: Text {
        Text("Priority & \(Text("800+").foregroundColor(tier.detailAccent).bold()) Style")
    }

    private var discountBenefitText: Text {
        Text("\(Text("\(tier.creditDiscount)% OFF ").foregroundColor(tier.detailAccent).bold())Lifetime Credits")
    }

    private func benefitRow(_ title: Text) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 15.5, weight: .black))
                .frame(width: 16)

            title
                .font(.system(size: 15, weight: .regular))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(height: 19)
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
                        Text(option.price(for: tier))
                            .font(.system(size: 18.5, weight: .heavy))
                            .foregroundStyle(.white)
                        Text(option.weeklyEquivalent(for: tier))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                } else {
                    Text(option.price(for: tier))
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
                        .offset(x: -5, y: -17)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title), \(option.price(for: tier))")
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

    private var annualDiscountBadge: some View {
        HStack(spacing: 5) {
            Text(tier == .pro ? "🎉" : "🔥")
                .font(.system(size: 15.5))
            Text("90% OFF")
                .font(.system(size: 14.5, weight: .heavy))
        }
        .foregroundStyle(.white)
        .frame(width: 100, height: 34)
        .background(
            LinearGradient(
                colors: tier.badgeGradient,
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(alignment: .bottomLeading) {
            PaywallBadgeTail()
                .fill(tier.badgeGradient[0])
                .frame(width: 7, height: 9)
                .offset(y: 7)
        }
    }

    private var continueButton: some View {
        Button(action: beginPurchase) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.56, blue: 0.0), Color(red: 1.0, green: 0.22, blue: 0.17)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                Rectangle()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 9, height: 72)
                    .rotationEffect(.degrees(31))
                    .offset(x: tier == .pro ? -150 : 88)

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
        .disabled(isPurchasing)
        .accessibilityIdentifier("membership-continue")
        .accessibilityValue(billing.productIdentifier(for: tier, isLoggedIn: usesLoggedInPaywall).rawValue)
    }

    private var footerLinks: some View {
        HStack(spacing: 12) {
            Button("Privacy") { showInformationAlert() }
            Text("|")
            Button("Terms") { showInformationAlert() }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 15, weight: .medium))
                Text("Cancel anytime")
            }
        }
        .font(.system(size: 14.5, weight: .regular))
        .foregroundStyle(Color(red: 0.47, green: 0.47, blue: 0.47))
    }

    private func beginPurchase() {
        guard !isPurchasing else { return }

        let productID = billing.productIdentifier(for: tier, isLoggedIn: usesLoggedInPaywall)
        isPurchasing = true

        Task {
            let outcome = await SubscriptionPurchaseService.purchase(productID)
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

    private func showInformationAlert() {
        purchaseAlert = SubscriptionPurchaseAlert(
            title: "StoreKit connection needed",
            message: "Restore, privacy, and terms actions still need their production destinations."
        )
    }

    private func closePaywall() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

struct CreditCenterView: View {
    @Binding var credits: Int

    @Environment(\.dismiss) private var dismiss
    @State private var checkedIn = false
    @State private var showCheckInSuccess = false
    @State private var showMembership = false

    private let dailyCredits = [20, 20, 50, 30, 30, 30, 100]

    var body: some View {
        NavigationStack {
            ZStack {
                RewardsBackground()

                VStack(spacing: 0) {
                    rewardsHeader

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Daily Free Credits")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(RewardsPalette.brown)

                            Text("up to 280 per week")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(RewardsPalette.muted)
                                .padding(.top, 6)

                            dailyCheckInCard
                                .padding(.top, 11)

                            RewardsActionRow(
                                title: "Welcome Gift",
                                creditAmount: 35,
                                icon: .asset("RewardsCreditToken", size: 32),
                                actionTitle: "Claimed",
                                enabled: false
                            ) {}
                            .padding(.top, 10)

                            ShareLink(item: "I am creating with Photo Revive AI") {
                                RewardsActionRow(
                                    title: "Share a creation",
                                    creditAmount: 10,
                                    icon: .asset("RewardsShareIcon", size: 42),
                                    actionTitle: "Claim",
                                    enabled: true,
                                    actionColor: RewardsPalette.red
                                ) {}
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 10)

                            NavigationLink {
                                InviteFriendsView(credits: $credits)
                            } label: {
                                RewardsInviteBanner()
                            }
                            .buttonStyle(TemplatePressStyle())
                            .accessibilityIdentifier("invite-friends-link")
                            .padding(.top, 10)

                            sectionTitle("Special Offer")
                                .padding(.top, 30)

                            RewardsActionRow(
                                title: "Save Up to 65%",
                                creditAmount: 400,
                                icon: .asset("RewardsGiftIcon", size: 42),
                                actionTitle: "Get",
                                enabled: true,
                                highlightOffer: true
                            ) {
                                showMembership = true
                            }
                            .padding(.top, 10)

                            sectionTitle("One-Time Rewards")
                                .padding(.top, 30)

                            RewardsActionRow(
                                title: "Enable Notifications",
                                creditAmount: 20,
                                icon: .asset("RewardsBellIcon", size: 42),
                                actionTitle: "Claimed",
                                enabled: false
                            ) {}
                            .padding(.top, 10)

                            RewardsActionRow(
                                title: "Follow TikTok",
                                creditAmount: 10,
                                icon: .asset("RewardsTikTokIcon", size: 42),
                                actionTitle: "Claimed",
                                enabled: false
                            ) {}
                            .padding(.top, 10)

                            RewardsActionRow(
                                title: "Follow Instagram",
                                creditAmount: 10,
                                icon: .instagram,
                                actionTitle: "Claimed",
                                enabled: false
                            ) {}
                            .padding(.top, 10)

                            RewardsActionRow(
                                title: "Follow X",
                                creditAmount: 10,
                                icon: .x,
                                actionTitle: "Claimed",
                                enabled: false
                            ) {}
                            .padding(.top, 10)
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
            MembershipPaywallView()
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

    private var dailyCheckInCard: some View {
        VStack(spacing: 13) {
            HStack(spacing: 7) {
                ForEach(Array(dailyCredits.enumerated()), id: \.offset) { index, amount in
                    let isHighlighted = index == 2 || index == 6
                    let isClaimedToday = checkedIn && index == 0

                    VStack(spacing: 6) {
                        Text("Day\(index + 1)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(
                                isHighlighted
                                    ? Color.white
                                    : isClaimedToday
                                        ? RewardsPalette.orange.opacity(0.36)
                                        : RewardsPalette.muted
                            )

                        Group {
                            if isClaimedToday {
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

                        Text("+\(amount)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(
                                isHighlighted
                                    ? Color.white
                                    : isClaimedToday
                                        ? RewardsPalette.orange.opacity(0.36)
                                        : RewardsPalette.orange
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .background(
                        isHighlighted
                            ? RewardsPalette.selectedDay
                            : isClaimedToday
                                ? RewardsPalette.claimedDay
                                : RewardsPalette.card,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                index == 0 && !isClaimedToday
                                    ? RewardsPalette.orange
                                    : RewardsPalette.orange.opacity(isClaimedToday ? 0.08 : 0.14),
                                lineWidth: index == 0 && !isClaimedToday ? 1.2 : 1
                            )
                    )
                }
            }

            Button {
                guard !checkedIn else { return }
                checkedIn = true
                credits += dailyCredits[0]
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCheckInSuccess = true
                }
            } label: {
                Text(checkedIn ? "Come Tomorrow" : "Check In")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 250, height: 44)
                    .background(
                        checkedIn
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
            .disabled(checkedIn)
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
                    Text("+\(dailyCredits[0]) credits")
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
    let action: () -> Void

    var body: some View {
        Button {
            if enabled { action() }
        } label: {
            HStack(spacing: 14) {
                RewardsActionIconView(icon: icon)

                VStack(alignment: .leading, spacing: 3) {
                    if highlightOffer {
                        (Text("Save Up to ") + Text("65%").foregroundStyle(RewardsPalette.red))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(RewardsPalette.ink)
                    } else {
                        Text(title)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(RewardsPalette.ink)
                    }

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

private struct RewardsInviteBanner: View {
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
                    Text("50")
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

    @State private var redemptionCode = ""
    @State private var showInfo = false
    @State private var showCopied = false
    @State private var showRedeemed = false

    private let invitationCode = "ydOGxtY"
    private let invitationURL = URL(string: "https://example.com/invite/ydOGxtY")!

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

                        ShareLink(item: invitationURL) {
                            Label("Invite Now", systemImage: "arrow.right")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(AppPalette.orange, in: Capsule())
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

                            Button("Redeem") {
                                credits += 50
                                redemptionCode = ""
                                showRedeemed = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(redemptionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        .alert("Invitation rewards", isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Both people earn 50 credits after sign-up and 100 credits after a qualifying subscription.")
        }
        .alert("Copied", isPresented: $showCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The invitation code is on your clipboard.")
        }
        .alert("Credits added", isPresented: $showRedeemed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("50 credits were added for this local UI flow.")
        }
    }

    private var invitationSteps: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                invitationStep("Share link", systemImage: "person.badge.plus")
                Image(systemName: "chevron.right.2")
                    .foregroundStyle(AppPalette.orange)
                invitationStep("Friend joins", systemImage: "person.crop.circle.badge.checkmark")
                Image(systemName: "chevron.right.2")
                    .foregroundStyle(AppPalette.orange)
                invitationStep("Earn rewards", systemImage: "gift.fill")
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("50 credits each when a friend signs up", systemImage: "diamond.fill")
                Label("100 credits each when a friend subscribes", systemImage: "diamond.fill")
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
}

struct SuggestionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var suggestion = ""
    @State private var email = ""
    @State private var selectedScreenshot: PhotosPickerItem?
    @State private var screenshotImage: UIImage?
    @State private var showFAQ = false
    @State private var showSubmitted = false

    private var canSubmit: Bool {
        !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && email.contains("@")
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
                        TextField(
                            "",
                            text: $email,
                            prompt: Text("name@example.com").foregroundStyle(.tertiary)
                        )
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Section("Screenshot") {
                        PhotosPicker(selection: $selectedScreenshot, matching: .images) {
                            HStack(spacing: 14) {
                                if let screenshotImage {
                                    Image(uiImage: screenshotImage)
                                        .resizable()
                                        .scaledToFill()
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
                            showSubmitted = true
                        } label: {
                            Text("Send Suggestion")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!canSubmit)
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
        .alert("Suggestion FAQ", isPresented: $showFAQ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Describe the style, subject and expected result. A reference screenshot is optional but helpful.")
        }
        .alert("Suggestion ready", isPresented: $showSubmitted) {
            Button("Done") {
                dismiss()
            }
        } message: {
            Text("The form UI is complete. Connect your feedback endpoint before shipping submissions.")
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
    var creditDiscount: Int { self == .pro ? 30 : 50 }
    var accent: Color { self == .pro ? Color.yellow : AppPalette.accent }

    var mediaStripAsset: String {
        self == .pro ? "PaywallProMediaStrip" : "PaywallProPlusMediaStrip"
    }

    var loggedInHeroAsset: String {
        self == .pro ? "OnboardingFusionBackground" : "OnboardingRestoreBackground"
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

    var badgeGradient: [Color] {
        self == .pro
            ? [Color(red: 0.93, green: 0.25, blue: 0.17), Color(red: 1.0, green: 0.43, blue: 0.02)]
            : [Color(red: 0.94, green: 0.24, blue: 0.16), Color(red: 0.96, green: 0.31, blue: 0.24)]
    }
}

private struct PaywallBadgeTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private enum MembershipBilling: String, CaseIterable, Identifiable {
    case annual
    case weekly

    var id: String { rawValue }
    var title: String { self == .annual ? "Annual Plan" : "Weekly Plan" }
    var loggedInTitle: String { self == .annual ? "Annual" : "Weekly" }

    func price(for tier: MembershipTier) -> String {
        switch (self, tier) {
        case (.annual, .pro): "$49.99"
        case (.annual, .proPlus): "$89.99"
        case (.weekly, .pro): "$9.99"
        case (.weekly, .proPlus): "$17.99"
        }
    }

    func weeklyEquivalent(for tier: MembershipTier) -> String {
        tier == .pro ? "Just $0.96/week" : "Just $1.73/week"
    }

    func loggedInAnnualPrice(for tier: MembershipTier) -> String {
        tier == .pro ? "$47.99" : "$89.99"
    }

    func loggedInTrailingPrice(for tier: MembershipTier) -> String {
        switch (self, tier) {
        case (.annual, .pro): "$0.92/week"
        case (.annual, .proPlus): "$1.73/week"
        case (.weekly, .pro): "$9.99/week"
        case (.weekly, .proPlus): "$17.99/week"
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
