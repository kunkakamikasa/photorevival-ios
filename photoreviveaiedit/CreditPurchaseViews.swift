import SwiftUI

/// The display catalog is intentionally separate from StoreKit configuration.
/// Add the consumable Product IDs here when they are available, then inject the
/// production purchase handler into `CreditStoreView` and `CreditExitOfferView`.
struct CreditPack: Identifiable, Hashable {
    let id: String
    let credits: Int
    let displayPrice: String
    let productID: String?
    let badge: String?

    var creditsLabel: String {
        credits.formatted()
    }
}

enum CreditProductCatalog {
    // TODO: Replace nil with the App Store consumable Product IDs.
    static let starterProductID: String? = nil
    static let creatorProductID: String? = nil
    static let studioProductID: String? = nil
    static let exitOfferProductID: String? = nil
    static let subscriberReturn1600ProductID: String? = nil

    static let packs: [CreditPack] = [
        CreditPack(
            id: "starter",
            credits: 250,
            displayPrice: "$6.99",
            productID: starterProductID,
            badge: nil
        ),
        CreditPack(
            id: "creator",
            credits: 700,
            displayPrice: "$14.99",
            productID: creatorProductID,
            badge: "MOST POPULAR"
        ),
        CreditPack(
            id: "studio",
            credits: 1_200,
            displayPrice: "$24.99",
            productID: studioProductID,
            badge: "BEST VALUE"
        )
    ]

    static let exitOfferBonus = 80
    static let exitOfferPack = CreditPack(
        id: "starter-exit-offer",
        credits: 330,
        displayPrice: "$6.99",
        productID: exitOfferProductID,
        badge: nil
    )

    static let subscriberReturnOffer = CreditPack(
        id: "subscriber-return-1600",
        credits: 1_600,
        displayPrice: "$29.99",
        productID: subscriberReturn1600ProductID,
        badge: "SUBSCRIBER EXCLUSIVE"
    )
}

struct CreditStoreView: View {
    let onClose: () -> Void
    var onPurchase: ((CreditPack) -> Void)?

    @State private var selectedPackID = "creator"
    @State private var offerEndsAt = Date.now.addingTimeInterval(15 * 60)
    @State private var showDetails = false
    @State private var showProductNotice = false

    private var selectedPack: CreditPack {
        CreditProductCatalog.packs.first { $0.id == selectedPackID }
            ?? CreditProductCatalog.packs[1]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CreditStoreBackground(size: proxy.size)

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        topBar

                        VStack(spacing: 9) {
                            Text("CREATE WITHOUT LIMITS")
                                .font(.system(size: 13, weight: .black))
                                .tracking(2.2)
                                .foregroundStyle(CreditStorePalette.gold)

                            Text("Bring every memory\nback to life")
                                .font(.system(size: 38, weight: .black, design: .rounded))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.78)
                                .lineLimit(2)

                            Text("One-time credit packs. Yours forever.")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 18)

                        packPicker
                            .padding(.top, 32)

                        offerClock
                            .padding(.top, 30)

                        purchaseButton
                            .padding(.top, 26)

                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.shield.fill")
                            Text("Secure purchase through the App Store")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.top, 12)
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom, 18))
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("credit-store-screen")
        .alert("About credits", isPresented: $showDetails) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Credits can be used for photo and video creations. Purchased credits do not expire and are used after recurring credits.")
        }
        .alert("Products coming next", isPresented: $showProductNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This purchase layout is ready. Add the consumable Product IDs to CreditProductCatalog to connect App Store checkout.")
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.30), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.44), lineWidth: 1))
            }
            .buttonStyle(TemplatePressStyle())
            .accessibilityLabel("Close credit store")
            .accessibilityIdentifier("credit-store-close")

            Spacer()

            Button { showDetails = true } label: {
                HStack(spacing: 7) {
                    Image("RewardsCreditToken")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 23, height: 23)
                    Text("How it works")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(.black.opacity(0.28), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(TemplatePressStyle())
            .accessibilityIdentifier("credit-store-details")
        }
        .padding(.horizontal, 19)
        .padding(.top, 10)
    }

    private var packPicker: some View {
        HStack(spacing: 10) {
            ForEach(CreditProductCatalog.packs) { pack in
                CreditPackCard(
                    pack: pack,
                    isSelected: selectedPackID == pack.id
                ) {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedPackID = pack.id
                    }
                }
            }
        }
        .padding(.horizontal, 15)
    }

    private var offerClock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let parts = countdownParts(at: timeline.date)
            VStack(spacing: 10) {
                Text("TODAY'S PACK PRICES END IN")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(.white.opacity(0.68))

                HStack(spacing: 8) {
                    CreditCountdownCell(value: parts.minutes, label: "MIN")
                    Text(":")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(CreditStorePalette.gold)
                        .offset(y: -7)
                    CreditCountdownCell(value: parts.seconds, label: "SEC")
                }
            }
        }
        .accessibilityIdentifier("credit-offer-countdown")
    }

    private var purchaseButton: some View {
        Button {
            if let onPurchase {
                onPurchase(selectedPack)
            } else {
                showProductNotice = true
            }
        } label: {
            HStack {
                Spacer()
                VStack(spacing: 1) {
                    Text("Get \(selectedPack.creditsLabel) credits")
                        .font(.system(size: 20, weight: .black))
                    Text(selectedPack.displayPrice)
                        .font(.system(size: 12, weight: .bold))
                        .opacity(0.78)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 23, weight: .bold))
            }
            .foregroundStyle(CreditStorePalette.buttonInk)
            .padding(.horizontal, 22)
            .frame(height: 62)
            .background(
                LinearGradient(
                    colors: [Color(red: 1.00, green: 0.82, blue: 0.35), Color(red: 1.00, green: 0.49, blue: 0.08)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .shadow(color: CreditStorePalette.gold.opacity(0.32), radius: 18, y: 8)
        }
        .buttonStyle(TemplatePressStyle())
        .padding(.horizontal, 20)
        .accessibilityIdentifier("credit-store-continue")
    }

    private func countdownParts(at date: Date) -> (minutes: String, seconds: String) {
        let remaining = max(Int(offerEndsAt.timeIntervalSince(date)), 0)
        return (
            String(format: "%02d", remaining / 60),
            String(format: "%02d", remaining % 60)
        )
    }
}

struct CreditExitOfferView: View {
    let onClose: () -> Void
    var onClaim: ((CreditPack) -> Void)?

    @State private var showProductNotice = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.52))
                    .ignoresSafeArea()
                    .onTapGesture { }

                VStack {
                    Spacer(minLength: 48)

                    ScrollView(.vertical) {
                        offerContent
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: min(proxy.size.height - 62, 690))
                    .background(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.45, green: 0.12, blue: 0.94), location: 0),
                                .init(color: Color(red: 0.28, green: 0.06, blue: 0.66), location: 0.56),
                                .init(color: Color(red: 0.12, green: 0.03, blue: 0.34), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.38), radius: 28, y: 16)
                    .overlay(alignment: .topTrailing) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background(.black.opacity(0.32), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.48), lineWidth: 1))
                        }
                        .buttonStyle(TemplatePressStyle())
                        .accessibilityLabel("Close bonus offer")
                        .accessibilityIdentifier("credit-exit-offer-close")
                        .offset(x: -12, y: 12)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 10))
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("credit-exit-offer")
        .alert("Products coming next", isPresented: $showProductNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The bonus offer is ready for its consumable Product ID. Checkout will be connected when that ID is provided.")
        }
    }

    private var offerContent: some View {
        VStack(spacing: 0) {
            Text("A little extra for you")
                .font(.system(size: 29, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 52)
                .padding(.top, 43)

            Text("Get \(CreditProductCatalog.exitOfferBonus) bonus credits with the starter pack today")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
                .padding(.top, 10)

            CreditGiftArtwork(bonus: CreditProductCatalog.exitOfferBonus)
                .frame(height: 245)
                .padding(.top, 2)

            HStack(spacing: 12) {
                Image("RewardsCreditToken")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 0) {
                    Text("330")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text("credits total")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                }

                Spacer()

                Text(CreditProductCatalog.exitOfferPack.displayPrice)
                    .font(.system(size: 26, weight: .black, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 19)
            .frame(height: 78)
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.86), lineWidth: 2)
            )
            .padding(.horizontal, 20)

            Button {
                if let onClaim {
                    onClaim(CreditProductCatalog.exitOfferPack)
                } else {
                    showProductNotice = true
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Claim bonus pack")
                        .font(.system(size: 20, weight: .black))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 23, weight: .bold))
                }
                .foregroundStyle(CreditStorePalette.buttonInk)
                .padding(.horizontal, 21)
                .frame(height: 61)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.00, green: 0.87, blue: 0.40), Color(red: 1.00, green: 0.55, blue: 0.04)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
            }
            .buttonStyle(TemplatePressStyle())
            .accessibilityIdentifier("credit-exit-offer-claim")
            .padding(.horizontal, 22)
            .padding(.top, 23)

            Text("Pay once. Credits never expire.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .padding(.top, 13)
                .padding(.bottom, 24)
        }
    }
}

private enum CreditStorePalette {
    static let gold = Color(red: 1.00, green: 0.69, blue: 0.20)
    static let buttonInk = Color(red: 0.12, green: 0.08, blue: 0.04)
}

private struct CreditStoreBackground: View {
    let size: CGSize

    var body: some View {
        ZStack {
            Image("MemoryPortrait")
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .saturation(0.28)
                .contrast(1.08)

            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.03, green: 0.04, blue: 0.10).opacity(0.54), location: 0),
                    .init(color: Color(red: 0.05, green: 0.05, blue: 0.12).opacity(0.76), location: 0.40),
                    .init(color: Color.black.opacity(0.96), location: 0.79)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color.orange.opacity(0.33), .clear],
                center: UnitPoint(x: 0.53, y: 0.38),
                startRadius: 10,
                endRadius: size.width * 0.72
            )

            Canvas { context, canvasSize in
                for index in 0..<45 {
                    let x = CGFloat((index * 73 + 29) % 101) / 101 * canvasSize.width
                    let y = CGFloat((index * 47 + 11) % 89) / 89 * canvasSize.height * 0.72
                    let diameter = CGFloat(index.isMultiple(of: 7) ? 3 : 1.4)
                    let rect = CGRect(x: x, y: y, width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(index.isMultiple(of: 3) ? 0.66 : 0.34)))
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

private struct CreditPackCard: View {
    let pack: CreditPack
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(CreditStorePalette.gold.opacity(0.13))
                        .frame(width: 57, height: 57)
                    Image("RewardsCreditToken")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 45, height: 45)
                }

                Text(pack.creditsLabel)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)

                Text("CREDITS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.54))

                Text(pack.displayPrice)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isSelected ? CreditStorePalette.gold : .white.opacity(0.82))
                    .padding(.top, 3)
            }
            .padding(.top, 19)
            .padding(.bottom, 17)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 190)
            .background(.white.opacity(isSelected ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(isSelected ? CreditStorePalette.gold : .white.opacity(0.22), lineWidth: isSelected ? 2.5 : 1)
            )
            .overlay(alignment: .top) {
                if let badge = pack.badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(CreditStorePalette.buttonInk)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(CreditStorePalette.gold, in: Capsule())
                        .offset(y: -11)
                }
            }
        }
        .buttonStyle(TemplatePressStyle())
        .accessibilityLabel("\(pack.credits) credits for \(pack.displayPrice)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("credit-pack-\(pack.id)")
    }
}

private struct CreditCountdownCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 25, weight: .black, design: .monospaced))
                .foregroundStyle(CreditStorePalette.gold)
                .frame(width: 66, height: 48)
                .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CreditStorePalette.gold.opacity(0.64), lineWidth: 1)
                )
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.48))
        }
    }
}

private struct CreditGiftArtwork: View {
    let bonus: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.25), Color.purple.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 128
                    )
                )
                .frame(width: 260, height: 260)

            sparkle("sparkles", x: -128, y: -45, size: 30)
            sparkle("star.fill", x: 132, y: -78, size: 16)
            sparkle("sparkle", x: 122, y: 70, size: 25)

            Image("RewardsCreditToken")
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .rotationEffect(.degrees(-18))
                .offset(x: -118, y: 60)

            Image("RewardsCreditToken")
                .resizable()
                .scaledToFit()
                .frame(width: 45, height: 45)
                .rotationEffect(.degrees(21))
                .offset(x: 126, y: 48)

            VStack(spacing: -3) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.92, green: 0.55, blue: 1.00), Color(red: 0.50, green: 0.13, blue: 0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 218, height: 52)
                    .overlay {
                        Text("EXTRA CREDITS")
                            .font(.system(size: 13, weight: .black))
                            .tracking(1.6)
                            .foregroundStyle(.white)
                    }
                    .rotationEffect(.degrees(-3))
                    .zIndex(2)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.79, green: 0.36, blue: 1.00), Color(red: 0.41, green: 0.08, blue: 0.77)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 230, height: 143)
                    .overlay {
                        VStack(spacing: -2) {
                            Text("+\(bonus)")
                                .font(.system(size: 61, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: Color(red: 0.25, green: 0.02, blue: 0.55), radius: 0, y: 4)
                            Text("BONUS")
                                .font(.system(size: 12, weight: .black))
                                .tracking(3)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    .overlay {
                        Rectangle()
                            .fill(CreditStorePalette.gold)
                            .frame(width: 19)
                            .opacity(0.88)
                    }
            }
            .shadow(color: .black.opacity(0.28), radius: 15, y: 11)
        }
    }

    private func sparkle(_ name: String, x: CGFloat, y: CGFloat, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(CreditStorePalette.gold)
            .shadow(color: CreditStorePalette.gold.opacity(0.55), radius: 7)
            .offset(x: x, y: y)
    }
}

#Preview("Credit Store") {
    CreditStoreView(onClose: {})
}

#Preview("Credit Exit Offer") {
    ZStack {
        PaperTextureBackground()
        CreditExitOfferView(onClose: {})
    }
}
