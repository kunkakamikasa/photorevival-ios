import AVFoundation
import SwiftUI

struct PaperTextureBackground: View {
    var body: some View {
        ZStack {
            AppPalette.surfaceCenter

            LinearGradient(
                stops: [
                    .init(color: AppPalette.surfaceEdge.opacity(0.52), location: 0),
                    .init(color: AppPalette.surfaceCenter.opacity(0.16), location: 0.24),
                    .init(color: AppPalette.backgroundTop.opacity(0.36), location: 0.50),
                    .init(color: AppPalette.surfaceCenter.opacity(0.12), location: 0.76),
                    .init(color: AppPalette.surfaceEdge.opacity(0.55), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.25), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 290
            )

            LinearGradient(
                colors: [Color.white.opacity(0.10), .clear, AppPalette.surfaceEdge.opacity(0.13)],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { context, size in
                for index in 0..<720 {
                    let xSeed = (index * 73 + index * index * 17) % 997
                    let ySeed = (index * 193 + index * index * 11) % 991
                    let diameter = CGFloat((index * 29) % 5 + 1) * 0.45
                    let rect = CGRect(
                        x: CGFloat(xSeed) / 997 * size.width,
                        y: CGFloat(ySeed) / 991 * size.height,
                        width: diameter,
                        height: diameter
                    )
                    let color = index.isMultiple(of: 3)
                        ? Color.white.opacity(0.12)
                        : AppPalette.surfaceEdge.opacity(0.09)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
            .blendMode(.softLight)
        }
        .ignoresSafeArea()
    }
}

struct BottomTabBar: View {
    @Binding var selection: AppTab
    var onSelect: ((AppTab) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    if let onSelect {
                        onSelect(tab)
                    } else {
                        withAnimation(.easeInOut(duration: 0.24)) { selection = tab }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 12, weight: selection == tab ? .bold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? .white : AppPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 57)
                    .background(selection == tab ? Color.black.opacity(0.18) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.25), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.74), lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 13, y: 6)
        .padding(.horizontal, 20)
        .padding(.bottom, -14)
    }
}

struct HomeDiscountBannerView: View {
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                Image("HomeDiscountBanner")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TemplatePressStyle())
            .accessibilityIdentifier("home-discount-banner")
            .overlay {
                GeometryReader { proxy in
                    HomeDiscountTapHint()
                        .position(
                            x: proxy.size.width * 0.958,
                            y: proxy.size.height * 0.755
                        )
                }
                .allowsHitTesting(false)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(.black.opacity(0.42), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.60), lineWidth: 0.7))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close home discount banner")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
    }
}

private struct HomeDiscountTapHint: View {
    @State private var isTapping = false

    var body: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 31, weight: .bold))
            .foregroundStyle(Color(red: 1.0, green: 0.89, blue: 0.73))
            .shadow(color: .white.opacity(0.8), radius: 2)
            .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
            .rotationEffect(.degrees(-11))
            .scaleEffect(isTapping ? 0.91 : 1.0)
            .offset(x: isTapping ? -2 : 1, y: isTapping ? -7 : 2)
            .animation(
                .easeInOut(duration: 0.58).repeatForever(autoreverses: true),
                value: isTapping
            )
            .onAppear {
                isTapping = true
            }
            .accessibilityHidden(true)
    }
}

struct MePage: View {
    let onCreate: () -> Void
    let onSettings: () -> Void
    @State private var kind = "Video"
    @State private var hasVideoRecord = true
    @State private var showPreview = false
    @State private var showNotice = false
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            meHeader

            if kind == "Video" && hasVideoRecord {
                videoRecordContent
                legalNotice
                    .padding(.top, 16)
                Spacer(minLength: 0)
            } else {
                emptyContent
                Spacer(minLength: 0)
                legalNotice
                    .padding(.bottom, 112)
            }
        }
        .fullScreenCover(isPresented: $showPreview) {
            MeVideoPreviewView(videoName: "baby_fly") {
                showPreview = false
            }
        }
        .alert(noticeTitle, isPresented: $showNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
    }

    private var meHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(["Video", "Photo"], id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { kind = item }
                    } label: {
                        Text(item)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(kind == item ? Color(red: 0.80, green: 0.29, blue: 0.25) : AppPalette.ink)
                            .frame(width: 94, height: 43)
                            .background(kind == item ? Color.white.opacity(0.46) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.white.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.70), lineWidth: 1))

            Spacer(minLength: 0)

            if kind == "Video" && hasVideoRecord {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hasVideoRecord = false
                    }
                } label: {
                    Text("Delete")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(AppPalette.ink)
                        .padding(.horizontal, 20)
                        .frame(height: 43)
                        .background(Color.white.opacity(0.48), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete generation")
            }

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.42), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 0)
    }

    private var videoRecordContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Baby Adventure")
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundStyle(Color(red: 0.31, green: 0.23, blue: 0.16))
                    Text("Dog Friends")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color(red: 0.31, green: 0.23, blue: 0.16))
                }

                Spacer(minLength: 8)

                Text("Yesterday")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Color(red: 0.31, green: 0.23, blue: 0.16))
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            MeVideoCard(videoName: "baby_fly", onOpen: { showPreview = true })
                .frame(maxWidth: 390)
                .padding(.horizontal, 20)
                .padding(.top, 0)

            HStack(spacing: 0) {
                Button {
                    presentNotice(title: "Saved", message: "The generated video is ready to save to your Photos library.")
                } label: {
                    Label("Save", systemImage: "arrow.down.to.line")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(AppPalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save generated video")

                Divider()
                    .frame(height: 50)

                Button {
                    presentNotice(title: "No Watermark", message: "Upgrade your membership to export without a watermark.")
                } label: {
                    Label("No Watermark", systemImage: "eraser")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(AppPalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove watermark")
            }
            .frame(height: 50)
            .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.72), lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 2)

            MeSharePanel()
                .padding(.horizontal, 20)
                .padding(.top, 4)
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 17) {
            VStack(spacing: 3) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 22, weight: .bold))
                Image(systemName: kind == "Video" ? "hand.draw" : "photo.badge.plus")
                    .font(.system(size: 67, weight: .ultraLight))
            }
            .foregroundStyle(AppPalette.brownInk.opacity(0.84))

            Text("There is nothing now")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppPalette.brownInk)
            Button {
                hasVideoRecord = true
                onCreate()
            } label: {
                Text("Create Now")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 29)
                    .frame(height: 52)
                    .background(AppPalette.accent, in: Capsule())
            }
            .accessibilityLabel("Create now")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 190)
    }

    private var legalNotice: some View {
        Text("You are responsible for your rendered content. Use our app legally and ethically. Our policies apply.")
            .font(.footnote)
            .foregroundStyle(AppPalette.brownInk)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }

    private func presentNotice(title: String, message: String) {
        noticeTitle = title
        noticeMessage = message
        showNotice = true
    }
}

private struct MeVideoCard: View {
    let videoName: String
    let onOpen: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black

            MeVideoWatermarkPattern()
                .allowsHitTesting(false)

            Button(action: onOpen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.54), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.76), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel("Open generated video")

            Button(action: onOpen) {
                Image(systemName: "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(.black.opacity(0.56), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityLabel("Play generated video")
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct MeVideoWatermarkPattern: View {
    private let placements: [(CGFloat, CGFloat)] = [
        (0.08, 0.16), (0.43, 0.18), (0.82, 0.22),
        (0.20, 0.49), (0.61, 0.52), (0.92, 0.61),
        (0.09, 0.80), (0.48, 0.82), (0.80, 0.86)
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(placements.enumerated()), id: \.offset) { _, placement in
                Text("Photo Revive AI")
                    .font(.system(size: max(10, proxy.size.width * 0.025), weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
                    .rotationEffect(.degrees(-17))
                    .position(
                        x: proxy.size.width * placement.0,
                        y: proxy.size.height * placement.1
                    )
            }
        }
    }
}

private struct MeSharePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Share to:")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(AppPalette.ink)

            HStack(spacing: 0) {
                shareLink(symbol: "message.fill", color: Color(red: 0.08, green: 0.78, blue: 0.27), label: "WhatsApp")
                shareLink(symbol: "bubble.left.and.bubble.right.fill", color: Color(red: 0.11, green: 0.81, blue: 0.25), label: "Messages")
                shareLink(symbol: "bolt.horizontal.circle.fill", color: Color(red: 0.43, green: 0.36, blue: 0.97), label: "Messenger")
                shareLink(symbol: "f.cursive", color: Color(red: 0.06, green: 0.37, blue: 0.95), label: "Facebook")
                shareLink(symbol: "camera.fill", color: Color(red: 0.90, green: 0.15, blue: 0.54), label: "Instagram")
                shareLink(symbol: "music.note", color: .black, label: "TikTok")
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.72), lineWidth: 1))
    }

    private func shareLink(symbol: String, color: Color, label: String) -> some View {
        ShareLink(item: "I am sharing a Photo Revive AI video") {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 45, height: 45)
                .background(color, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.64), lineWidth: 1))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share to \(label)")
    }
}

private struct MeVideoPreviewView: View {
    let videoName: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            LoopingVideoView(resourceName: videoName, videoGravity: .resizeAspect)
                .ignoresSafeArea(edges: .horizontal)

            MeVideoWatermarkPattern()
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.black.opacity(0.46), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.66), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close generated video")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

enum UtilitySheet: String, Identifiable {
    case membership
    case credits
    case gift
    case settings

    var id: String { rawValue }
}

struct UtilitySheetView: View {
    let sheet: UtilitySheet
    @Binding var credits: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(AppPalette.orange)
                Text(title)
                    .font(.title2.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if sheet == .gift {
                    Button("Claim Gift") {
                        credits += 20
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if sheet == .membership {
                    Button("Start 7-day free trial") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(sheet == .settings ? "Settings" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(AppPalette.accent)
    }

    private var title: String {
        switch sheet {
        case .membership: "Unlock Photo Revive Pro"
        case .credits: "\(credits) Credits"
        case .gift: "Daily Gift"
        case .settings: "App Settings"
        }
    }

    private var message: String {
        switch sheet {
        case .membership: "Create more videos, remove watermarks and unlock every template."
        case .credits: "Credits are used when an AI photo or video is rendered."
        case .gift: "Claim 20 free credits and come back tomorrow for more."
        case .settings: "Notification, export and account settings will appear here."
        }
    }

    private var icon: String {
        switch sheet {
        case .membership: "sparkles"
        case .credits: "diamond.fill"
        case .gift: "gift.fill"
        case .settings: "gearshape.fill"
        }
    }
}
