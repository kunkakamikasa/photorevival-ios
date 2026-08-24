import AVFoundation
import SwiftUI
import UIKit

struct DiscoveryPage: View {
    let tab: AppTab
    let videoSections: [TemplateSection]
    let imageSections: [TemplateSection]
    let homeSections: [TemplateSection]
    let heroEntries: [TemplateDetailEntry]
    let isLoadingTemplates: Bool
    let credits: Int
    let onSelectTemplate: (TemplateItem) -> Void
    let onSelectCarousel: (TemplateDetailEntry) -> Void
    let onMembership: () -> Void
    let onCredits: () -> Void
    let onGift: () -> Void
    let onSuggestion: () -> Void
    let onSummerOffer: () -> Void
    let isSubscribed: Bool
    let isLoggedIn: Bool
    let onLogin: () -> Void
    let onFixedFeature: (FixedFeature) -> Void

    var body: some View {
        Group {
            if tab == .home {
                HomeDiscoveryView(
                    sections: homeSections,
                    heroEntries: heroEntries,
                    isLoadingTemplates: isLoadingTemplates,
                    credits: credits,
                    onSelectTemplate: onSelectTemplate,
                    onSelectCarousel: onSelectCarousel,
                    onMembership: onMembership,
                    onCredits: onCredits,
                    onGift: onGift,
                    onSummerOffer: onSummerOffer,
                    isSubscribed: isSubscribed,
                    isLoggedIn: isLoggedIn,
                    onLogin: onLogin,
                    onFixedFeature: onFixedFeature
                )
            } else {
                StandardDiscoveryView(
                    tab: tab,
                    sections: tab == .video ? videoSections : imageSections,
                    heroEntries: heroEntries,
                    isLoadingTemplates: isLoadingTemplates,
                    credits: credits,
                    onSelectTemplate: onSelectTemplate,
                    onSelectCarousel: onSelectCarousel,
                    onMembership: onMembership,
                    onCredits: onCredits,
                    onGift: onGift,
                    onSuggestion: onSuggestion,
                    onFixedFeature: onFixedFeature
                )
            }
        }
    }
}

private struct HomeDiscoveryView: View {
    let sections: [TemplateSection]
    let heroEntries: [TemplateDetailEntry]
    let isLoadingTemplates: Bool
    let credits: Int
    let onSelectTemplate: (TemplateItem) -> Void
    let onSelectCarousel: (TemplateDetailEntry) -> Void
    let onMembership: () -> Void
    let onCredits: () -> Void
    let onGift: () -> Void
    let onSummerOffer: () -> Void
    let isSubscribed: Bool
    let isLoggedIn: Bool
    let onLogin: () -> Void
    let onFixedFeature: (FixedFeature) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                HomeHeroCarousel(
                    entries: heroEntries,
                    credits: credits,
                    onSelect: onSelectCarousel,
                    onMembership: onMembership,
                    onCredits: onCredits,
                    onGift: onGift,
                    onSummerOffer: onSummerOffer,
                    isSubscribed: isSubscribed,
                    isLoggedIn: isLoggedIn,
                    onLogin: onLogin
                )

                HomeQuickActionStrip(onSelect: onFixedFeature)
                    .padding(.top, -38)
                    .zIndex(2)

                VStack(spacing: 25) {
                    if sections.isEmpty && isLoadingTemplates {
                        TemplateSectionsSkeleton()
                    } else {
                        ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                            TemplateSectionView(
                                section: section,
                                badge: TemplateSectionBadgePolicy.badge(
                                    for: section,
                                    at: index,
                                    on: .home
                                ),
                                onSelect: onSelectTemplate
                            )
                        }
                    }
                }
                .padding(.top, 24)
            }
            .padding(.bottom, 124)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }
}

private struct StandardDiscoveryView: View {
    let tab: AppTab
    let sections: [TemplateSection]
    let heroEntries: [TemplateDetailEntry]
    let isLoadingTemplates: Bool
    let credits: Int
    let onSelectTemplate: (TemplateItem) -> Void
    let onSelectCarousel: (TemplateDetailEntry) -> Void
    let onMembership: () -> Void
    let onCredits: () -> Void
    let onGift: () -> Void
    let onSuggestion: () -> Void
    let onFixedFeature: (FixedFeature) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                DiscoveryHeader(
                    title: tab.pageTitle,
                    credits: credits,
                    onMembership: onMembership,
                    onCredits: onCredits,
                    onGift: onGift
                )

                if tab == .video {
                    VideoModeStrip()
                        .padding(.top, 10)
                }

                if !heroEntries.isEmpty {
                    FramedHeroCarousel(
                        entries: heroEntries,
                        height: tab == .video ? 219 : 196,
                        accessibilityLabel: tab == .video ? "Try AI Video" : "Try AI Photo",
                        onSelect: onSelectCarousel
                    )
                    .padding(.top, tab == .video ? 0 : 5)
                }

                if tab == .photo {
                    PhotoToolStrip(onSelect: onFixedFeature)
                        .padding(.top, 18)
                }

                VStack(spacing: 25) {
                    if sections.isEmpty && isLoadingTemplates {
                        TemplateSectionsSkeleton()
                    } else {
                        ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                            TemplateSectionView(
                                section: section,
                                badge: TemplateSectionBadgePolicy.badge(
                                    for: section,
                                    at: index,
                                    on: tab
                                ),
                                onSelect: onSelectTemplate
                            )
                        }
                    }
                }
                .padding(.top, 24)

                if tab == .photo {
                    SuggestTemplateCallToAction(action: onSuggestion)
                        .padding(.top, 42)
                }
            }
            .padding(.bottom, 124)
        }
        .scrollIndicators(.hidden)
    }
}

private struct TemplateSectionsSkeleton: View {
    private let headingWidths: [CGFloat] = [132, 108, 146]

    var body: some View {
        VStack(spacing: 25) {
            ForEach(0..<3, id: \.self) { index in
                TemplateSectionSkeleton(headingWidth: headingWidths[index])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading templates")
    }
}

private struct TemplateSectionSkeleton: View {
    let headingWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                SkeletonBlock(width: headingWidth, height: 25, cornerRadius: 6)

                Spacer(minLength: 4)

                SkeletonBlock(width: 22, height: 22, cornerRadius: 7)
            }
            .padding(.horizontal, 20)

            GeometryReader { proxy in
                let portraitWidth = min(120, max(108, (proxy.size.width - 67) / 3))

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 11) {
                        ForEach(0..<4, id: \.self) { _ in
                            TemplateCoverSkeleton(width: portraitWidth, height: 180)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
            .frame(height: 180)
        }
    }
}

private struct TemplateCoverSkeleton: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.58),
                        AppPalette.surfaceEdge.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .bottom) {
                SkeletonBlock(width: width * 0.58, height: 14, cornerRadius: 5)
                    .padding(.bottom, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppPalette.surfaceEdge.opacity(0.12), lineWidth: 1)
            )
            .frame(width: width, height: height)
    }
}

private struct SkeletonBlock: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppPalette.surfaceEdge.opacity(0.10), lineWidth: 1)
            )
            .frame(width: width, height: height)
    }
}

private struct SuggestTemplateCallToAction: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Didn't find the style you like?")
                .font(.title3)
                .foregroundStyle(AppPalette.ink.opacity(0.76))

            Button(action: action) {
                Text("Suggest a Template")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 34)
                    .frame(height: 52)
                    .background(AppPalette.ink, in: Capsule())
            }
            .buttonStyle(TemplatePressStyle())
            .accessibilityIdentifier("suggest-template")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
}

private struct DiscoveryHeader: View {
    let title: String
    let credits: Int
    let onMembership: () -> Void
    let onCredits: () -> Void
    let onGift: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 21, weight: .heavy))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            RewardControls(
                credits: credits,
                onMembership: onMembership,
                onCredits: onCredits,
                onGift: onGift
            )
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
    }
}

private struct RewardControls: View {
    let credits: Int
    let onMembership: () -> Void
    let onCredits: () -> Void
    let onGift: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 0) {
                Button(action: onMembership) {
                    Text("PRO")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 59, height: 34)
                        .background(AppPalette.accent, in: Capsule())
                }
                .accessibilityLabel("Open Pro membership")

                Button(action: onCredits) {
                    HStack(spacing: 4) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppPalette.orange)
                        Text("\(credits)")
                            .font(.system(size: 15, weight: .bold))
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(AppPalette.accent)
                            .frame(width: 20, height: 20)
                            .background(.white.opacity(0.88), in: Circle())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(height: 34)
                }
                .accessibilityLabel("View credits")
            }
            .padding(2)
            .background(Color.black.opacity(0.20), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1))

            Button(action: onGift) {
                AnimatedGiftIcon(size: 46)
            }
            .accessibilityLabel("Open daily gift")
        }
        .buttonStyle(.plain)
    }
}

private struct AnimatedGiftIcon: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let cycleDuration = 1.65
            let cycleProgress = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
            let motion = CGFloat((1 - cos(cycleProgress * 2 * .pi)) / 2)
            let bodyLift = -motion * 3.0
            let lidLift = -motion * 4.5
            let lidRotation = Angle.degrees(-motion * 8.0)

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.22)))
                    .overlay(Circle().stroke(Color.white.opacity(0.88), lineWidth: 1.1))

                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.78, blue: 0.20),
                                    Color(red: 1.00, green: 0.58, blue: 0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 23)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.7)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.white.opacity(0.94))
                                .frame(width: 32, height: 5)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color(red: 0.96, green: 0.33, blue: 0.08))
                                .frame(width: 6, height: 23)
                        }
                        .offset(y: 6 + bodyLift)

                    ZStack {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.00, green: 0.66, blue: 0.07),
                                        Color(red: 0.96, green: 0.36, blue: 0.06)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 35, height: 8)
                            .overlay {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(Color.white.opacity(0.94))
                                    .frame(width: 35, height: 3)
                            }

                        Capsule()
                            .fill(Color(red: 1.00, green: 0.47, blue: 0.08))
                            .frame(width: 13, height: 7)
                            .rotationEffect(.degrees(-30))
                            .offset(x: -6, y: -8)

                        Capsule()
                            .fill(Color(red: 1.00, green: 0.47, blue: 0.08))
                            .frame(width: 13, height: 7)
                            .rotationEffect(.degrees(30))
                            .offset(x: 6, y: -8)

                        Circle()
                            .fill(Color(red: 0.96, green: 0.33, blue: 0.08))
                            .frame(width: 7, height: 7)
                            .offset(y: -8)
                    }
                    .offset(y: -7 + lidLift)
                    .rotationEffect(lidRotation, anchor: .bottomLeading)
                }
                .frame(width: 43, height: 43)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct HomeHeroCarousel: View {
    let entries: [TemplateDetailEntry]
    let credits: Int
    let onSelect: (TemplateDetailEntry) -> Void
    let onMembership: () -> Void
    let onCredits: () -> Void
    let onGift: () -> Void
    let onSummerOffer: () -> Void
    let isSubscribed: Bool
    let isLoggedIn: Bool
    let onLogin: () -> Void
    @State private var selectedPage = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $selectedPage) {
                Button(action: onSummerOffer) {
                    SummerCampaignHero()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tag(0)
                .accessibilityLabel("Open 65% summer offer")

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        TemplateMediaView(item: entry.displayItem, gravity: .resizeAspectFill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(index + 1)
                    .accessibilityLabel("Open \(entry.displayItem.title)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            LinearGradient(
                colors: [AppPalette.surfaceCenter.opacity(0.62), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 116)
            .allowsHitTesting(false)

            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: AppPalette.surfaceCenter.opacity(0.42), location: 0.43),
                        .init(color: AppPalette.surfaceCenter, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    stops: [
                        .init(color: AppPalette.surfaceEdge.opacity(0.48), location: 0),
                        .init(color: .clear, location: 0.27),
                        .init(color: .clear, location: 0.73),
                        .init(color: AppPalette.surfaceEdge.opacity(0.50), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(
                    LinearGradient(colors: [.clear, .clear, .black], startPoint: .top, endPoint: .bottom)
                )
            }
            .frame(height: 148)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            Group {
                if isSubscribed || isLoggedIn {
                    RewardControls(
                        credits: credits,
                        onMembership: onMembership,
                        onCredits: onCredits,
                        onGift: onGift
                    )
                } else {
                    GuestHomeControls(onLogin: onLogin, onGift: onGift)
                }
            }
            .padding(.top, 57)
            .padding(.trailing, 17)

            Button {
                if selectedPage == 0 {
                    onSummerOffer()
                } else if entries.indices.contains(selectedPage - 1) {
                    onSelect(entries[selectedPage - 1])
                }
            } label: {
                Text("Try Now")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 17)
                    .frame(height: 34)
                    .background(.black.opacity(0.36), in: Capsule())
                    .overlay(
                        Capsule().stroke(
                            LinearGradient(colors: [.yellow, AppPalette.accent], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1
                        )
                    )
            }
            .buttonStyle(TemplatePressStyle())
            .padding(.trailing, 18)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            PageDots(count: entries.count + 1, selection: selectedPage)
                .padding(.leading, 19)
                .padding(.bottom, 72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 365)
        .clipped()
        .task {
            await advanceCarousel(
                count: entries.count + 1,
                selection: $selectedPage,
                intervalNanoseconds: 10_000_000_000
            )
        }
    }
}

private struct GuestHomeControls: View {
    let onLogin: () -> Void
    let onGift: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onLogin) {
                HStack(spacing: 6) {
                    Image("RewardsCreditToken")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)

                    Text("Free Use")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color(red: 1, green: 0.36, blue: 0.31), in: Capsule())
            }
            .accessibilityLabel("Free Use")

            Button(action: onGift) {
                AnimatedGiftIcon(size: 54)
            }
            .accessibilityLabel("Open daily gift")
        }
        .buttonStyle(.plain)
    }
}

private struct FramedHeroCarousel: View {
    let entries: [TemplateDetailEntry]
    let height: CGFloat
    let accessibilityLabel: String
    let onSelect: (TemplateDetailEntry) -> Void
    @State private var selectedPage = 0

    var body: some View {
        ZStack {
            TabView(selection: $selectedPage) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        ZStack {
                            TemplateMediaView(item: entry.displayItem, gravity: .resizeAspectFill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            LinearGradient(
                                colors: [.clear, .black.opacity(0.28)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                    .buttonStyle(.plain)
                    .tag(index)
                    .accessibilityLabel(accessibilityLabel)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Button {
                guard entries.indices.contains(selectedPage) else { return }
                onSelect(entries[selectedPage])
            } label: {
                Text("Try Now")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 36)
                    .background(.black.opacity(0.38), in: Capsule())
                    .overlay(
                        Capsule().stroke(
                            LinearGradient(colors: [.yellow, AppPalette.accent], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1
                        )
                    )
            }
            .buttonStyle(TemplatePressStyle())
            .padding(15)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            PageDots(count: entries.count, selection: selectedPage)
                .padding(.leading, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
        .task { await advanceCarousel(count: entries.count, selection: $selectedPage) }
    }
}

private struct PageDots: View {
    let count: Int
    let selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == selection ? Color.white : Color.white.opacity(0.48))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == selection ? 1.08 : 1)
                    .animation(.easeInOut(duration: 0.22), value: selection)
            }
        }
    }
}

@MainActor
private func advanceCarousel(
    count: Int,
    selection: Binding<Int>,
    intervalNanoseconds: UInt64 = 4_000_000_000
) async {
    guard count > 1 else { return }
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: intervalNanoseconds)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            selection.wrappedValue = (selection.wrappedValue + 1) % count
        }
    }
}

private struct AnimatedFeatureBadge: View {
    enum Size {
        case compact
        case card
        case section

        var height: CGFloat {
            switch self {
            case .compact: 18
            case .card: 21
            case .section: 20
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .compact: 9
            case .card: 10
            case .section: 11
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .compact: 6
            case .card: 7
            case .section: 7
            }
        }
    }

    let label: String
    let size: Size
    @State private var isPresented = false

    init(_ label: String, size: Size) {
        self.label = label.uppercased()
        self.size = size
    }

    private var isHot: Bool { label == "HOT" }
    private var isSectionBadge: Bool { size == .section && label == "NEW" }

    var body: some View {
        Group {
            if isSectionBadge {
                HStack(spacing: 2) {
                    Image(systemName: "link")
                        .font(.system(size: size.fontSize, weight: .bold))
                        .foregroundStyle(AppPalette.accent)
                        .rotationEffect(.degrees(-18))

                    badgeShape
                }
            } else {
                badgeShape
            }
        }
        .fixedSize()
        // Animate the whole badge, including the section NEW link icon. The
        // delayed task keeps the initial collapsed frame from being merged
        // into the first layout transaction on a cold launch.
        .scaleEffect(
            x: isPresented ? 1 : (isHot ? 0.08 : 0.02),
            y: isPresented ? 1 : (isHot ? 0.08 : 1),
            anchor: isHot || isSectionBadge ? .center : .trailing
        )
        .offset(x: isPresented || isHot ? 0 : 10)
        .opacity(isPresented ? 1 : 0)
        .accessibilityLabel(label)
        .task {
            guard !isPresented else { return }
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }

            if isHot {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.62, blendDuration: 0.08)) {
                    isPresented = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.62)) {
                    isPresented = true
                }
            }
        }
    }

    @ViewBuilder
    private var badgeShape: some View {
        let isBlack = isSectionBadge
        let usesTail = isHot && size == .section

        ZStack {
            if usesTail {
                HotBadgeShape()
                    .fill(AppPalette.accent)
            } else {
                Capsule()
                    .fill(isHot ? AppPalette.accent : (isBlack ? AppPalette.ink : Color(red: 1.0, green: 0.76, blue: 0.03)))
            }

            Text(label)
                .font(.system(size: size.fontSize, weight: .heavy))
                .foregroundStyle(isHot || isBlack ? .white : .black)
                .padding(.horizontal, size.horizontalPadding)
        }
        .frame(height: size.height)
    }
}

private struct HotBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height * 0.18, 3.5)
        let tailWidth = min(9, rect.width * 0.24)
        let tailHeight = min(5, rect.height * 0.26)
        let bodyRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)

        var path = Path(roundedRect: bodyRect, cornerRadius: radius, style: .continuous)
        path.move(to: CGPoint(x: rect.minX + tailWidth * 0.95, y: bodyRect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.minX + tailWidth * 0.58, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + tailWidth * 1.85, y: bodyRect.maxY - 1))
        path.closeSubpath()
        return path
    }
}

private struct HomeQuickActionStrip: View {
    let onSelect: (FixedFeature) -> Void

    private let actions: [(FixedFeature, TemplateItem)] = [
        (.oneTapRestore, TemplateCatalog.memory),
        (.enhanceVideo, TemplateCatalog.enhanceVideo),
        (.photoToVideo, TemplateCatalog.photoToVideo),
        (.aiImage, TemplateCatalog.gptImage),
        (.fusion, TemplateCatalog.fusion),
        (.enhancePhoto, TemplateCatalog.enhancePhoto),
        (.textToVideo, TemplateCatalog.textToVideoWhale)
    ]

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let cardWidth = max(108, (proxy.size.width - 64) / 3)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(actions.enumerated()), id: \.element.0) { index, action in
                            let comparisonCoverIDs: Set<String> = [
                                TemplateCatalog.memory.id,
                                TemplateCatalog.enhanceVideo.id,
                                TemplateCatalog.enhancePhoto.id
                            ]
                            let mediaGravity: AVLayerVideoGravity = comparisonCoverIDs.contains(action.1.id)
                                ? .resizeAspect
                                : .resizeAspectFill

                            Button {
                                onSelect(action.0)
                            } label: {
                                VStack(spacing: 7) {
                                    ZStack(alignment: .topTrailing) {
                                        TemplateMediaView(item: action.1, gravity: mediaGravity)
                                            .frame(width: cardWidth, height: 66)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                        if let badge = TemplateBadgePolicy.badge(for: action.1, at: index, on: .home) {
                                            AnimatedFeatureBadge(badge, size: .card)
                                                .offset(x: -4, y: 4)
                                        }
                                    }
                                    Text(action.0.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppPalette.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                }
                                .frame(width: cardWidth)
                            }
                            .buttonStyle(TemplatePressStyle())
                            .accessibilityLabel(action.0.title)
                            .accessibilityIdentifier("fixed-feature-\(action.0.id)")
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("home-fixed-features")
            }
            .frame(height: 92)

            HStack(spacing: 0) {
                Capsule()
                    .fill(AppPalette.surfaceEdge.opacity(0.72))
                    .frame(width: 38, height: 8)
                Capsule()
                    .fill(Color.white.opacity(0.46))
                    .frame(width: 38, height: 8)
            }
            .clipShape(Capsule())
        }
        .frame(height: 110)
    }
}

private struct TemplateSectionView: View {
    let section: TemplateSection
    let badge: String?
    let onSelect: (TemplateItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Text(section.title)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)

                if let badge {
                    AnimatedFeatureBadge(badge, size: .section)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppPalette.ink.opacity(0.78))
            }
            .padding(.horizontal, 20)

            GeometryReader { proxy in
                let portraitWidth = min(120, max(108, (proxy.size.width - 67) / 3))

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 11) {
                        ForEach(section.items) { item in
                            TemplateCoverCard(
                                item: item,
                                portraitWidth: portraitWidth
                            ) {
                                onSelect(item)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
            .frame(height: section.items.map(\.orientation).contains(.portrait) ? 180 : 116)
        }
    }
}

struct TemplateCoverCard: View {
    let item: TemplateItem
    let badge: String?
    var portraitWidth: CGFloat = 110
    let action: () -> Void

    private var cardSize: CGSize {
        item.orientation == .landscape
            ? CGSize(width: 174, height: 116)
            : CGSize(width: portraitWidth, height: 180)
    }

    init(item: TemplateItem, badge: String? = nil, portraitWidth: CGFloat = 110, action: @escaping () -> Void) {
        self.item = item
        self.badge = TemplateBadgeValue.normalized(badge ?? item.badge)
        self.portraitWidth = portraitWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                TemplateMediaView(item: item, gravity: .resizeAspectFill)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.76)],
                    startPoint: .init(x: 0.5, y: 0.56),
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                .zIndex(1)

                if let badge {
                    AnimatedFeatureBadge(badge, size: .card)
                        .padding(7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .zIndex(3)
                }

            }
            .frame(width: cardSize.width, height: cardSize.height)
            .overlay(alignment: .bottom) {
                Text(item.title)
                    .font(.system(size: item.orientation == .landscape ? 15 : 16, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 7)
                    .padding(.bottom, 9)
                    .shadow(color: .black.opacity(0.42), radius: 2, y: 1)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(TemplatePressStyle())
        .accessibilityIdentifier("template-\(item.id)")
        .accessibilityLabel(item.title)
    }
}

struct TemplateMediaView: View {
    let item: TemplateItem
    var gravity: AVLayerVideoGravity

    private var effectiveGravity: AVLayerVideoGravity {
        // Comparison covers must preserve the full before/after frame. The
        // surrounding catalog often asks for aspect-fill, which would crop
        // these comparison assets inside portrait or compact cards.
        let comparisonVideoNames: Set<String> = [
            "restore_comparison_cover",
            "enhance_comparison_cover",
            "enhance_photo_comparison_cover"
        ]
        return comparisonVideoNames.contains(item.videoName ?? "")
            ? .resizeAspect
            : gravity
    }

    var body: some View {
        ZStack {
            TemplateMediaLoadingPlaceholder()

            if let comparisonCover = item.comparisonCover {
                TemplateComparisonView(cover: comparisonCover)
            } else if let coverImageURL = item.coverImageURL {
                RemoteTemplateImage(url: coverImageURL)
            } else if !item.imageName.isEmpty {
                Image(item.imageName)
                    .resizable()
                    .scaledToFill()
            }

            // Image filters can reuse catalog entries that also have a legacy
            // video preview name. Their cover must remain a still image.
            if item.generationKind == .video {
                if let coverVideoURL = item.coverVideoURL {
                    RemoteLoopingVideoView(url: coverVideoURL, videoGravity: effectiveGravity)
                        .allowsHitTesting(false)
                } else if let videoName = item.videoName {
                    LoopingVideoView(resourceName: videoName, videoGravity: effectiveGravity)
                        .allowsHitTesting(false)
                }
            }
        }
        .clipped()
    }
}

struct TemplateComparisonView: View {
    let cover: TemplateComparisonCover
    var allowsInteraction = false
    var imageContentMode: ContentMode = .fill

    private let frameInterval = 1.0 / 30.0
    @State private var draggedProgress: CGFloat?

    var body: some View {
        TimelineView(.periodic(from: .now, by: frameInterval)) { context in
            GeometryReader { proxy in
                let progress = draggedProgress ?? sweepProgress(at: context.date)
                let width = proxy.size.width
                let height = proxy.size.height

                Group {
                    if allowsInteraction {
                        comparisonContent(width: width, height: height, progress: progress)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        draggedProgress = clampedProgress(value.location.x / max(width, 1))
                                    }
                                    .onEnded { _ in
                                        draggedProgress = nil
                                    }
                            )
                    } else {
                        comparisonContent(width: width, height: height, progress: progress)
                    }
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Before and after comparison")
        .accessibilityHint(allowsInteraction ? "Drag left or right to compare" : "")
    }

    private func sweepProgress(at date: Date) -> CGFloat {
        let legDuration = max(0.8, cover.duration)
        let cycleDuration = legDuration * 2
        let elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleDuration)
        let normalized = elapsed < legDuration
            ? elapsed / legDuration
            : 2 - (elapsed / legDuration)
        return CGFloat(min(max(normalized, 0), 1))
    }

    private func clampedProgress(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }

    private func comparisonContent(width: CGFloat, height: CGFloat, progress: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RemoteTemplateImage(url: cover.afterURL, imageContentMode: imageContentMode)
                .frame(width: width, height: height)

            RemoteTemplateImage(url: cover.beforeURL, imageContentMode: imageContentMode)
                .frame(width: width, height: height)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: width * progress, height: height)
                }

            Rectangle()
                .fill(.white)
                .frame(width: 2, height: height)
                .offset(x: min(max(width * progress - 1, 0), max(width - 2, 0)))
                .shadow(color: .black.opacity(0.30), radius: 1)
        }
    }
}

private struct RemoteTemplateImage: View {
    let url: URL
    var imageContentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                if imageContentMode == .fit {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else if didFail {
                TemplateMediaUnavailablePlaceholder()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        didFail = false
        image = nil

        if let cachedImage = TemplateImageCache.images.object(forKey: url as NSURL) {
            image = cachedImage
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled,
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let decodedImage = UIImage(data: data) else {
                didFail = true
                return
            }

            let pixelCost = Int(decodedImage.size.width * decodedImage.scale)
                * Int(decodedImage.size.height * decodedImage.scale)
                * 4
            TemplateImageCache.images.setObject(decodedImage, forKey: url as NSURL, cost: pixelCost)
            image = decodedImage
        } catch {
            guard !Task.isCancelled else { return }
            didFail = true
        }
    }
}

private enum TemplateImageCache {
    static let images: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 30
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()
}

private struct TemplateMediaLoadingPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.88, blue: 0.69),
                    Color(red: 0.93, green: 0.77, blue: 0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ProgressView()
                .controlSize(.large)
                .tint(AppPalette.surfaceEdge.opacity(0.34))
                .scaleEffect(1.12)
        }
    }
}

private struct TemplateMediaUnavailablePlaceholder: View {
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.83, blue: 0.63)

            Image(systemName: "photo")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(AppPalette.surfaceEdge.opacity(0.36))
        }
    }
}

struct TemplatePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.07 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.76), value: configuration.isPressed)
    }
}

private struct PhotoToolStrip: View {
    let onSelect: (FixedFeature) -> Void

    private let tools = [
        ("Restore &\nColorize", "photo.badge.checkmark", FixedFeature.oneTapRestore),
        ("Enhance\nPhoto", "wand.and.stars", FixedFeature.enhancePhoto),
        ("Image to\nImage", "person.crop.rectangle.stack", FixedFeature.imageToImage),
        ("Text to\nImage", "text.below.photo", FixedFeature.textToImage)
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(Array(tools.enumerated()), id: \.element.0) { index, tool in
                    Button { onSelect(tool.2) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tool.1)
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Color(red: 1.0, green: 0.70, blue: 0.30), in: RoundedRectangle(cornerRadius: 11))

                            Text(tool.0)
                                .font(.system(size: 13, weight: .bold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(AppPalette.ink)
                                .lineLimit(2)
                        }
                        .padding(8)
                        .frame(width: 102, height: 96)
                        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            if let badge = TemplateBadgePolicy.badge(
                                for: TemplateItem(id: tool.2.id, title: tool.0),
                                at: index,
                                on: .photo
                            ) {
                                AnimatedFeatureBadge(badge, size: .compact)
                                    .offset(y: -9)
                            }
                        }
                    }
                    .buttonStyle(TemplatePressStyle())
                    .accessibilityIdentifier("photo-fixed-feature-\(tool.2.id)")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
    }
}

private struct VideoModeSelectionShape: Shape {
    func path(in rect: CGRect) -> Path {
        let shoulder: CGFloat = min(10, rect.width * 0.10)
        let radius: CGFloat = min(14, rect.height * 0.30)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder + radius, y: rect.minY),
            control: CGPoint(x: rect.minX + shoulder, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - shoulder - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct VideoModeStrip: View {
    @State private var mode = "Photo To Video"
    private let modes = ["Photo To\nVideo", "Enhance\nVideo", "Fusion", "Text To\nVideo"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(modes, id: \.self) { item in
                let normalized = item.replacingOccurrences(of: "\n", with: " ")
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { mode = normalized }
                } label: {
                    Text(item)
                        .font(.system(size: 16, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(mode == normalized ? .white : AppPalette.ink)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background {
                            if mode == normalized {
                                VideoModeSelectionShape()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.82, green: 0.61, blue: 0.40),
                                                Color(red: 0.74, green: 0.49, blue: 0.29)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, -6)
    }
}
