import SwiftUI

struct SuperPrizeOfferView: View {
    let onClose: () -> Void
    @AppStorage("isSubscribed") private var isSubscribed = false
    @State private var isPurchasing = false
    @State private var purchaseAlert: SubscriptionPurchaseAlert?

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
            let outcome = await SubscriptionPurchaseService.purchase(.superPrizeWeekly)
            isPurchasing = false

            switch outcome {
            case .purchased:
                isSubscribed = true
                onClose()
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
    @AppStorage("isSubscribed") private var isSubscribed = false
    @State private var remainingHundredths = 60 * 100 - 1
    @State private var isPurchasing = false
    @State private var purchaseAlert: SubscriptionPurchaseAlert?

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
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
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background(Color.black.opacity(0.48), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
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
                        colors: [Color(red: 1, green: 0.65, blue: 0.12), Color(red: 0.65, green: 0.29, blue: 0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            VStack(spacing: 10) {
                Text("◆ PRO")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 36)
                    .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 8))
                    .offset(y: -20)

                HStack(alignment: .top, spacing: 18) {
                    benefitColumn(["Priority", "No Watermark", "30% OFF Credit"])
                    benefitColumn(["800+ styles", "Ad-Free", "260 per week"])
                }
                .padding(.top, -15)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.orange.opacity(0.55), lineWidth: 1))

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("56%")
                    .font(.system(size: 72, weight: .heavy))
                Text("OFF")
                    .font(.system(size: 32, weight: .heavy))
            }
            .foregroundStyle(
                LinearGradient(colors: [AppPalette.accent, AppPalette.orange], startPoint: .leading, endPoint: .trailing)
            )

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$24.99")
                        .font(.system(size: 35, weight: .bold))
                    Text("first year")
                        .font(.headline)
                }
                Text("Then $49.99/year")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            CountdownView(hundredths: remainingHundredths)

            Button {
                beginPurchase()
            } label: {
                Text(isPurchasing ? "Connecting..." : "Try Now")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.black.opacity(0.88), in: Capsule())
            }
            .buttonStyle(TemplatePressStyle())
            .disabled(isPurchasing)
            .accessibilityIdentifier("limited-offer-try-now")
        }
        .padding(22)
        .background(
            LinearGradient(colors: [Color(red: 1, green: 0.96, blue: 0.84), .white], startPoint: .top, endPoint: .center),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .shadow(color: .black.opacity(0.24), radius: 22, y: 10)
    }

    private func beginPurchase() {
        guard !isPurchasing else { return }

        isPurchasing = true
        Task {
            let outcome = await SubscriptionPurchaseService.purchase(.limitedTimeOfferYearly)
            isPurchasing = false

            switch outcome {
            case .purchased:
                isSubscribed = true
                onClose()
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
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 52)
                    .background(AppPalette.accent.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                if index < parts.count - 1 {
                    Text(":")
                        .font(.title2.bold())
                        .foregroundStyle(AppPalette.accent)
                }
            }
        }
        .accessibilityLabel("Offer countdown")
    }
}

struct SummerSalePaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isSubscribed") private var isSubscribed = false
    @State private var selectedPlan: SummerPlan = .annual
    @State private var isPurchasing = false
    @State private var purchaseAlert: SubscriptionPurchaseAlert?

    var body: some View {
        ZStack {
            SummerBeachBackdrop()

            LinearGradient(
                colors: [.white.opacity(0.14), Color(red: 1, green: 0.94, blue: 0.80).opacity(0.82), .white.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            SummerPalmDecor()

            GeometryReader { proxy in
                let horizontalPadding: CGFloat = 20
                let continueHorizontalPadding: CGFloat = 29
                let cardSpacing: CGFloat = 24
                let cardWidth = (proxy.size.width - horizontalPadding * 2 - cardSpacing) / 2

                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            closeButton
                            Spacer()
                            Button("Restore") { showInformationAlert() }
                                .font(.headline)
                                .foregroundStyle(Color(red: 0.45, green: 0.24, blue: 0.08))
                                .padding(.horizontal, 18)
                                .frame(height: 44)
                                .background(.white.opacity(0.72), in: Capsule())
                                .overlay(alignment: .trailing) {
                                    LinearGradient(
                                        colors: [.clear, .yellow.opacity(0.76), .white.opacity(0.10)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: 34, height: 36)
                                    .clipShape(Capsule())
                                    .blur(radius: 2)
                                    .allowsHitTesting(false)
                                }
                                .accessibilityIdentifier("summer-offer-restore")
                        }
                        .padding(.horizontal, horizontalPadding)

                        Text("Congratulations")
                            .font(.system(size: 34, weight: .heavy))
                            .italic()
                            .foregroundStyle(Color(red: 0.96, green: 0.58, blue: 0.02))
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                            .padding(.top, 15)

                        HStack(spacing: 8) {
                            Text("—✦")
                                .foregroundStyle(AppPalette.orange)
                            Text("You've got a Special gift!")
                                .foregroundStyle(AppPalette.ink)
                            Text("✦—")
                                .foregroundStyle(AppPalette.orange)
                        }
                            .font(.headline)
                            .minimumScaleFactor(0.78)
                            .lineLimit(1)
                            .padding(.top, 8)

                        SummerCoupon()
                            .frame(width: proxy.size.width, height: proxy.size.width * 780 / 1290)
                            .padding(.top, 35)

                        HStack(spacing: cardSpacing) {
                            SummerPlanCard(plan: .weekly, selectedPlan: $selectedPlan)
                                .frame(width: cardWidth)
                            SummerPlanCard(plan: .annual, selectedPlan: $selectedPlan)
                                .frame(width: cardWidth)
                        }
                        .padding(.top, 34)

                        Spacer(minLength: 82)

                        Button(action: beginPurchase) {
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
                            .frame(height: 56)
                            .background(
                                LinearGradient(colors: [AppPalette.orange, Color.red], startPoint: .leading, endPoint: .trailing),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(TemplatePressStyle())
                        .disabled(isPurchasing)
                        .accessibilityIdentifier("summer-offer-continue")
                        .accessibilityValue(selectedPlan.productIdentifier.rawValue)
                        .padding(.horizontal, continueHorizontalPadding)

                        Label("Cancel anytime", systemImage: "checkmark.shield")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.ink.opacity(0.75))
                            .padding(.top, 12)
                            .padding(.bottom, 12)
                    }
                    .frame(width: proxy.size.width)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.light)
        .accessibilityIdentifier("summer-sale-screen")
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

        let productID = selectedPlan.productIdentifier
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
            message: "Restore still needs its production StoreKit restore flow."
        )
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.title2.weight(.light))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.72), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close summer offer")
    }
}

private enum SummerPlan: String, CaseIterable, Identifiable {
    case weekly
    case annual

    var id: String { rawValue }
    var title: String { self == .weekly ? "Weekly Plan" : "Annual Plan" }
    var priceAmount: String { self == .weekly ? "$9.99" : "$39.99" }
    var pricePeriod: String { self == .weekly ? "/week" : "/year" }
    var dailyAmount: String { self == .weekly ? "$1.43" : "$0.11" }
    var productIdentifier: SubscriptionProductID {
        self == .weekly ? .specialGiftWeekly : .specialGiftYearly
    }
}

private struct SummerPlanCard: View {
    let plan: SummerPlan
    @Binding var selectedPlan: SummerPlan

    var body: some View {
        Button { selectedPlan = plan } label: {
            VStack(spacing: 0) {
                Text(plan.title)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(plan.priceAmount)
                        .font(.system(size: plan == .annual ? 23 : 21, weight: .heavy))
                    Text(plan.pricePeriod)
                        .font(.system(size: plan == .annual ? 15 : 14, weight: .regular))
                }
                    .foregroundStyle(AppPalette.ink)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .padding(.top, 14)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(plan.dailyAmount)
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
                    .frame(height: 39)
                    .background(Color.yellow.opacity(0.24))
            }
            .padding(.top, 32)
            .frame(maxWidth: .infinity)
            .frame(height: 188)
            .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(selectedPlan == plan ? Color.red : AppPalette.orange.opacity(0.7), lineWidth: selectedPlan == plan ? 4 : 1)
            )
            .overlay(alignment: .top) {
                if plan == .annual {
                    ZStack(alignment: .center) {
                        Image("SummerFlame")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 68, height: 58)
                            .offset(x: -48, y: -50)

                        Text("Most popular")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 36)
                            .background(LinearGradient(colors: [Color.red, AppPalette.accent], startPoint: .top, endPoint: .bottom), in: Capsule())
                    }
                    .offset(y: -18)
                }
            }
        }
        .buttonStyle(TemplatePressStyle())
        .accessibilityLabel(plan.title)
        .accessibilityValue(selectedPlan == plan ? "Selected" : "Not selected")
    }
}

private struct SummerCoupon: View {
    var body: some View {
        Image("SummerCouponArtwork")
            .resizable()
            .scaledToFit()
    }
}

struct SummerCampaignHero: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("SummerBeachBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                VStack(spacing: 2) {
                    Text("Today's Hot Rewards")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(
                            LinearGradient(colors: [AppPalette.orange, Color.red], startPoint: .leading, endPoint: .trailing)
                        )
                        .minimumScaleFactor(0.66)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        Text("Save up to")
                            .font(.headline.bold())
                            .foregroundStyle(AppPalette.accent)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(.white.opacity(0.88), in: Capsule())
                            .overlay(Capsule().stroke(AppPalette.accent.opacity(0.55), lineWidth: 1))

                        Text("65%")
                            .font(.system(size: 76, weight: .heavy))
                            .foregroundStyle(
                                LinearGradient(colors: [.yellow, AppPalette.orange, Color.red], startPoint: .top, endPoint: .bottom)
                            )
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 3)
                    }

                    HStack(spacing: 48) {
                        Image(systemName: "seal.fill")
                        Image(systemName: "star.fill")
                    }
                    .font(.title)
                    .foregroundStyle(Color(red: 0.89, green: 0.40, blue: 0.13))
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 104)
            }
        }
        .clipped()
        .accessibilityIdentifier("summer-campaign-hero")
    }
}

private struct SummerBeachBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            Image("SummerBeachBackground")
                .resizable()
                .scaledToFill()
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

private struct SummerPalmDecor: View {
    var body: some View {
        GeometryReader { proxy in
            Image("SummerPalmRight")
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width * 200 / 1290)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
