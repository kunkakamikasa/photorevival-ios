import SwiftUI

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
    static let starterProductID: String? = "basic300credits"
    static let creatorProductID: String? = "basic900credits"
    static let studioProductID: String? = "basic1400credits"
    static let exitOfferProductID: String? = "callback377"
    static let subscriberReturn1600ProductID: String? = "surprise1600credits"

    static let packs: [CreditPack] = [
        CreditPack(
            id: "starter",
            credits: 300,
            displayPrice: "—",
            productID: starterProductID,
            badge: nil
        ),
        CreditPack(
            id: "creator",
            credits: 900,
            displayPrice: "—",
            productID: creatorProductID,
            badge: "MOST POPULAR"
        ),
        CreditPack(
            id: "studio",
            credits: 1_400,
            displayPrice: "—",
            productID: studioProductID,
            badge: "BEST VALUE"
        )
    ]

    static let exitOfferBonus = 77
    static let exitOfferPack = CreditPack(
        id: "starter-exit-offer",
        credits: 377,
        displayPrice: "—",
        productID: exitOfferProductID,
        badge: nil
    )

    static let subscriberReturnOffer = CreditPack(
        id: "subscriber-return-1600",
        credits: 1_600,
        displayPrice: "—",
        productID: subscriberReturn1600ProductID,
        badge: "SUBSCRIBER EXCLUSIVE"
    )
}

struct CreditStoreView: View {
    let onClose: () -> Void
    var onPurchase: ((CreditPack) -> Void)?
    var onPurchased: ((Int) -> Void)?

    @State private var selectedPackID = "creator"
    @StateObject private var priceStore = StoreProductPriceStore.shared
    @State private var showDetails = false
    @State private var isPurchasing = false
    @State private var purchaseAlert: CreditPurchaseAlert?
    @State private var purchaseTask: Task<Void, Never>?

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

                        purchaseButton
                            .padding(.top, 30)

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
        .alert(item: $purchaseAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onDisappear {
            purchaseTask?.cancel()
        }
        .task {
            await priceStore.load(
                productIDs: CreditProductCatalog.packs.compactMap(\.productID)
            )
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: cancelPurchaseAndClose) {
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
                    displayPrice: displayedPrice(for: pack),
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

    private var purchaseButton: some View {
        Button {
            if let onPurchase {
                onPurchase(selectedPack)
            } else {
                beginPurchase(selectedPack)
            }
        } label: {
            HStack {
                Spacer()
                VStack(spacing: 1) {
                    Text(isPurchasing ? "Connecting..." : "Get \(selectedPack.creditsLabel) credits")
                        .font(.system(size: 20, weight: .black))
                    Text(displayedPrice(for: selectedPack))
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
        .disabled(isPurchasing)
        .padding(.horizontal, 20)
        .accessibilityIdentifier("credit-store-continue")
    }

    private func displayedPrice(for pack: CreditPack) -> String {
        priceStore.displayPrice(for: pack.productID, fallback: pack.displayPrice)
    }

    private func beginPurchase(_ pack: CreditPack) {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseTask = Task {
            let outcome = await CreditPurchaseService.purchase(
                pack,
                promotion: CreditPurchasePromotion.store(pack: pack)
            )
            guard !Task.isCancelled else { return }
            isPurchasing = false
            switch outcome {
            case .purchased(let credits):
                onPurchased?(credits)
            case .cancelled:
                break
            case .pending:
                purchaseAlert = CreditPurchaseAlert(
                    title: "Purchase pending",
                    message: "Apple is still processing this purchase. Your credits will be added after confirmation."
                )
            case .unavailable:
                purchaseAlert = CreditPurchaseAlert(
                    title: "Product unavailable",
                    message: "This credit pack is not currently available from the App Store."
                )
            case .failed(let message):
                purchaseAlert = CreditPurchaseAlert(title: "Purchase unavailable", message: message)
            }
        }
    }

    private func cancelPurchaseAndClose() {
        purchaseTask?.cancel()
        isPurchasing = false
        onClose()
    }
}

struct CreditExitOfferView: View {
    let onClose: () -> Void
    var onClaim: ((CreditPack) -> Void)?
    var onPurchased: ((Int) -> Void)?

    @State private var isPurchasing = false
    @State private var purchaseAlert: CreditPurchaseAlert?
    @State private var purchaseTask: Task<Void, Never>?
    @StateObject private var priceStore = StoreProductPriceStore.shared

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
                    .frame(maxHeight: min(proxy.size.height - 62, 610))
                    .background(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.38, green: 0.05, blue: 0.95), location: 0),
                                .init(color: Color(red: 0.30, green: 0.04, blue: 0.73), location: 0.50),
                                .init(color: Color(red: 0.13, green: 0.02, blue: 0.39), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.38), radius: 28, y: 16)
                    .padding(.horizontal, 8)
                    .padding(.bottom, -max(proxy.safeAreaInsets.bottom - 8, 0))
                }

                Button(action: cancelPurchaseAndClose) {
                    ZStack {
                        Color.clear

                        Image(systemName: "xmark")
                            .font(.system(size: 23, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(.ultraThinMaterial, in: Circle())
                            .background(.white.opacity(0.16), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1.2))
                            .shadow(color: .black.opacity(0.34), radius: 8, y: 3)
                    }
                    .frame(width: 70, height: 70)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close bonus offer")
                .accessibilityIdentifier("credit-exit-offer-close")
                .position(
                    x: proxy.size.width - 43,
                    y: max(35, proxy.size.height - min(proxy.size.height - 62, 610) - 8)
                )
                .zIndex(100)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("credit-exit-offer")
        .alert(item: $purchaseAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onDisappear {
            purchaseTask?.cancel()
        }
        .task {
            await priceStore.load(
                productIDs: [CreditProductCatalog.exitOfferPack.productID].compactMap { $0 }
            )
        }
    }

    private var offerContent: some View {
        VStack(spacing: 0) {
            Text("Wait! Don't Miss This 🎁")
                .font(.system(size: 31, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 28)
                .padding(.top, 42)

            (
                Text("Enjoy ")
                    .foregroundColor(.white.opacity(0.88))
                + Text("\(CreditProductCatalog.exitOfferBonus) bonus credits")
                    .foregroundColor(Color(red: 1.00, green: 0.79, blue: 0.16))
                    .fontWeight(.bold)
                + Text(" with your\npurchase today")
                    .foregroundColor(.white.opacity(0.88))
            )
                .font(.system(size: 18, weight: .medium))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 34)
                .padding(.top, 15)

            CreditGiftArtwork(bonus: CreditProductCatalog.exitOfferBonus)
                .frame(height: 235)
                .padding(.top, 1)

            HStack(spacing: 12) {
                Image("RewardsCreditToken")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 43, height: 43)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("377")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text("credits")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer()

                Text(priceStore.displayPrice(
                    for: CreditProductCatalog.exitOfferPack.productID,
                    fallback: CreditProductCatalog.exitOfferPack.displayPrice
                ))
                    .font(.system(size: 26, weight: .black, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 64)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.95), lineWidth: 2.2)
            )
            .padding(.horizontal, 19)

            Button {
                if let onClaim {
                    onClaim(CreditProductCatalog.exitOfferPack)
                } else {
                    beginPurchase()
                }
            } label: {
                HStack {
                    Spacer()
                    Text(isPurchasing ? "Connecting..." : "Claim My Bonus")
                        .font(.system(size: 20, weight: .black))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 23, weight: .bold))
                }
                .foregroundStyle(CreditStorePalette.buttonInk)
                .padding(.horizontal, 21)
                .frame(height: 54)
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
            .disabled(isPurchasing)
            .accessibilityIdentifier("credit-exit-offer-claim")
            .padding(.horizontal, 20)
            .padding(.top, 40)

            Text("Pay once, never expire.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.90))
                .padding(.top, 16)
                .padding(.bottom, 22)
        }
    }

    private func beginPurchase() {
        guard !isPurchasing else { return }
        isPurchasing = true
        let pack = CreditProductCatalog.exitOfferPack
        purchaseTask = Task {
            let outcome = await CreditPurchaseService.purchase(
                pack,
                promotion: CreditPurchasePromotion.callback377
            )
            guard !Task.isCancelled else { return }
            isPurchasing = false
            switch outcome {
            case .purchased(let credits):
                onPurchased?(credits)
                onClose()
            case .cancelled:
                break
            case .pending:
                purchaseAlert = CreditPurchaseAlert(
                    title: "Purchase pending",
                    message: "Apple is still processing this purchase. Your credits will be added after confirmation."
                )
            case .unavailable:
                purchaseAlert = CreditPurchaseAlert(
                    title: "Product unavailable",
                    message: "The 377-credit callback offer is not currently available from the App Store."
                )
            case .failed(let message):
                purchaseAlert = CreditPurchaseAlert(title: "Purchase unavailable", message: message)
            }
        }
    }

    private func cancelPurchaseAndClose() {
        purchaseTask?.cancel()
        isPurchasing = false
        onClose()
    }
}

private struct CreditPurchaseAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum CreditStorePalette {
    static let gold = Color(red: 1.00, green: 0.69, blue: 0.20)
    static let buttonInk = Color(red: 0.12, green: 0.08, blue: 0.04)
}

private struct CreditStoreBackground: View {
    let size: CGSize

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.10)

            LoopingVideoView(resourceName: "CreditStoreBackgroundVideo")
                .frame(width: size.width, height: size.height)
                .clipped()
                .allowsHitTesting(false)

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
    let displayPrice: String
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

                Text(displayPrice)
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
        .accessibilityLabel("\(pack.credits) credits for \(displayPrice)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("credit-pack-\(pack.id)")
    }
}

private struct CreditGiftArtwork: View {
    let bonus: Int

    var body: some View {
        ZStack {
            Image("CallbackBonusGift")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 235)
                .offset(y: 10)

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(red: 0.39, green: 0.05, blue: 0.93), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 22)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [.clear, Color(red: 0.25, green: 0.03, blue: 0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 25)
            }
            .allowsHitTesting(false)

            Text("EXTRA GIFT")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(height: 31)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.73, green: 0.31, blue: 0.98), Color(red: 0.47, green: 0.08, blue: 0.83)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .rotationEffect(.degrees(-2))
                .shadow(color: .black.opacity(0.24), radius: 5, y: 3)
                .offset(y: -81)

            VStack(spacing: -5) {
                Text("+\(bonus)")
                    .font(.system(size: 68, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(red: 0.90, green: 0.75, blue: 1.00)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color(red: 0.27, green: 0.02, blue: 0.54).opacity(0.80), radius: 0, y: 4)

                Text("Lucky Credits")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.28, green: 0.05, blue: 0.55))
            }
            .offset(y: -21)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Extra \(bonus) credit bonus")
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
