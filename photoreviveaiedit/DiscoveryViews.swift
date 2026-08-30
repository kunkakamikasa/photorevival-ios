import AVFoundation
import SwiftUI
import UIKit

struct DiscoveryPage: View {
    let tab: AppTab
    let videoSections: [TemplateSection]
    let imageSections: [TemplateSection]
    let homeSections: [TemplateSection]
    let heroEntries: [TemplateDetailEntry]
    let homeQuickActions: [HomeQuickAction]
    let videoModeActions: [HomeQuickAction]
    let homeHeroPromotion: CMSHomeHeroPromotion?
    let isLoadingTemplates: Bool
    let credits: Int
    let onSelectTemplate: (TemplateItem) -> Void
    let onSelectCarousel: (TemplateDetailEntry) -> Void
    let onMembership: () -> Void
    let onCredits: () -> Void
    let onGift: () -> Void
    let onSuggestion: () -> Void
    let onHeroPromotion: (CMSHomeHeroPromotion) -> Void
    let isSubscribed: Bool
    let isLoggedIn: Bool
    let onLogin: () -> Void
    let onFixedFeature: (FixedFeature) -> Void

    var body: some View {
        GeometryReader { proxy in
            Group {
                if tab == .home {
                    HomeDiscoveryView(
                        sections: homeSections,
                        heroEntries: heroEntries,
                        quickActions: homeQuickActions,
                        heroPromotion: homeHeroPromotion,
                        isLoadingTemplates: isLoadingTemplates,
                        credits: credits,
                        onSelectTemplate: onSelectTemplate,
                        onSelectCarousel: onSelectCarousel,
                        onMembership: onMembership,
                        onCredits: onCredits,
                        onGift: onGift,
                        onSuggestion: onSuggestion,
                        onHeroPromotion: onHeroPromotion,
                        isSubscribed: isSubscribed,
                        isLoggedIn: isLoggedIn,
                        onLogin: onLogin,
                        onFixedFeature: onFixedFeature
                    )
                } else {
                    StandardDiscoveryView(
                        tab: tab,
                        containerWidth: proxy.size.width,
                        sections: tab == .video ? videoSections : imageSections,
                        heroEntries: heroEntries,
                        videoModeActions: videoModeActions,
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
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct HomeDiscoveryView: View {
    let sections: [TemplateSection]
    let heroEntries: [TemplateDetailEntry]
    let quickActions: [HomeQuickAction]
    let heroPromotion: CMSHomeHeroPromotion?
    let isLoadingTemplates: Bool
    let credits: Int
    let onSelectTemplate: (TemplateItem) -> Void
    let onSelectCarousel: (TemplateDetailEntry) -> Void
    let onMembership: () -> Void
    let onCredits: () -> Void
    let onGift: () -> Void
    let onSuggestion: () -> Void
    let onHeroPromotion: (CMSHomeHeroPromotion) -> Void
    let isSubscribed: Bool
    let isLoggedIn: Bool
    let onLogin: () -> Void
    let onFixedFeature: (FixedFeature) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                HomeHeroCarousel(
                    entries: heroEntries,
                    promotion: heroPromotion,
                    isLoading: isLoadingTemplates,
                    credits: credits,
                    onSelect: onSelectCarousel,
                    onMembership: onMembership,
                    onCredits: onCredits,
                    onGift: onGift,
                    onHeroPromotion: onHeroPromotion,
                    isSubscribed: isSubscribed,
                    isLoggedIn: isLoggedIn,
                    onLogin: onLogin
                )

                if isLoadingTemplates || !quickActions.isEmpty {
                    HomeQuickActionStrip(
                        actions: quickActions,
                        isLoading: isLoadingTemplates && quickActions.isEmpty,
                        onSelect: onFixedFeature
                    )
                    .padding(.top, -38)
                    .zIndex(2)
                }

                LazyVStack(spacing: 25) {
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

                SuggestTemplateCallToAction(action: onSuggestion)
                    .padding(.top, 42)
            }
            .padding(.bottom, 124)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }
}

private struct StandardDiscoveryView: View {
    let tab: AppTab
    let containerWidth: CGFloat
    let sections: [TemplateSection]
    let heroEntries: [TemplateDetailEntry]
    let videoModeActions: [HomeQuickAction]
    let isLoadingTemplates: Bool
    let credits: Int
    let onSelectTemplate: (TemplateItem) -> Void
    let onSelectCarousel: (TemplateDetailEntry) -> Void
    let onMembership: () -> Void
    let onCredits: () -> Void
    let onGift: () -> Void
    let onSuggestion: () -> Void
    let onFixedFeature: (FixedFeature) -> Void
    @State private var selectedVideoMode: FixedFeature?

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
                    VideoModeStrip(
                        actions: videoModeActions,
                        containerWidth: containerWidth,
                        selection: $selectedVideoMode
                    )
                        .padding(.top, 10)

                    if let action = selectedVideoMode.flatMap({ selectedMode in
                        videoModeActions.first { $0.feature == selectedMode }
                    }) ?? videoModeActions.first {
                        VideoModeHero(
                            action: action,
                            containerWidth: containerWidth,
                            onSelect: onFixedFeature
                        )
                    }
                }

                if tab == .photo {
                    Group {
                        if heroEntries.isEmpty && isLoadingTemplates {
                            HeroCarouselSkeleton(cornerRadius: 14)
                                .frame(height: 196)
                                .padding(.horizontal, 20)
                        } else if !heroEntries.isEmpty {
                            FramedHeroCarousel(
                                entries: heroEntries,
                                height: 196,
                                accessibilityLabel: "Try AI Photo",
                                onSelect: onSelectCarousel
                            )
                        }
                    }
                    .padding(.top, 5)
                }

                if tab == .photo {
                    PhotoToolStrip(onSelect: onFixedFeature)
                        .padding(.top, 18)
                }

                LazyVStack(spacing: 25) {
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

                if tab == .photo || tab == .video {
                    SuggestTemplateCallToAction(action: onSuggestion)
                        .padding(.top, 42)
                }
            }
            .frame(width: containerWidth, alignment: .leading)
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
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Button(action: onMembership) {
                    Text("PRO")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 41, height: 24)
                        .background(AppPalette.accent, in: Capsule())
                }
                .accessibilityLabel("Open Pro membership")

                Button(action: onCredits) {
                    HStack(spacing: 3) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppPalette.orange)
                        Text("\(credits)")
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(AppPalette.accent)
                            .frame(width: 14, height: 14)
                            .background(.white.opacity(0.88), in: Circle())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .frame(height: 24)
                }
                .accessibilityLabel("View credits")
            }
            .padding(1.5)
            .background(Color.black.opacity(0.20), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1))

            Button(action: onGift) {
                AnimatedGiftIcon(size: 46)
                    .scaleEffect(0.7)
                    .frame(width: 32, height: 32)
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
    let promotion: CMSHomeHeroPromotion?
    let isLoading: Bool
    let credits: Int
    let onSelect: (TemplateDetailEntry) -> Void
    let onMembership: () -> Void
    let onCredits: () -> Void
    let onGift: () -> Void
    let onHeroPromotion: (CMSHomeHeroPromotion) -> Void
    let isSubscribed: Bool
    let isLoggedIn: Bool
    let onLogin: () -> Void
    @State private var selectedPage = 0

    private var promotionPageCount: Int { promotion == nil ? 0 : 1 }
    private var pageCount: Int { entries.count + promotionPageCount }
    private var carouselContentID: String {
        ([promotion?.id ?? "no-promotion"] + entries.map(\.id)).joined(separator: "|")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if pageCount == 0 && isLoading {
                    HeroCarouselSkeleton()
                } else {
                    TabView(selection: $selectedPage) {
                        if let promotion {
                            Button { onHeroPromotion(promotion) } label: {
                                ConfiguredPromotionImage(
                                    url: promotion.coverImageURL,
                                    showsSkeletonWhileLoading: true
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .tag(0)
                            .accessibilityLabel(promotion.accessibilityLabel)
                        }

                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            Button {
                                onSelect(entry)
                            } label: {
                                TemplateMediaView(
                                    item: entry.displayItem,
                                    gravity: .resizeAspectFill,
                                    playsVideo: selectedPage == index + promotionPageCount
                                )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .tag(index + promotionPageCount)
                            .accessibilityLabel("Open \(entry.displayItem.title)")
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .id(carouselContentID)
                }
            }

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

            if pageCount > 0 {
                Button {
                    if let promotion, selectedPage == 0 {
                        onHeroPromotion(promotion)
                    } else {
                        let entryIndex = selectedPage - promotionPageCount
                        if entries.indices.contains(entryIndex) {
                            onSelect(entries[entryIndex])
                        }
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

                PageDots(count: pageCount, selection: selectedPage)
                    .padding(.leading, 19)
                    .padding(.bottom, 72)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(height: 365)
        .clipped()
        .onChange(of: carouselContentID) { _, _ in
            selectedPage = 0
        }
        .task(id: carouselContentID) {
            await advanceCarousel(
                count: pageCount,
                selection: $selectedPage,
                intervalNanoseconds: 10_000_000_000
            )
        }
    }
}

struct ConfiguredPromotionImage: View {
    let url: URL
    var showsSkeletonWhileLoading = false
    var contentMode: UIView.ContentMode = .scaleAspectFill
    @State private var image: UIImage?
    @State private var didFail = false
    @State private var resolvedURL: URL?

    private var displayedImage: UIImage? {
        resolvedURL == url ? image : nil
    }

    private var displaysFailure: Bool {
        resolvedURL == url && didFail
    }

    var body: some View {
        ZStack {
            if displayedImage == nil && !displaysFailure {
                if showsSkeletonWhileLoading {
                    HeroCarouselSkeleton()
                } else {
                    ZStack {
                        Color(red: 0.94, green: 0.78, blue: 0.56)
                        ProgressView().tint(.white)
                    }
                }
            }

            if let image = displayedImage {
                AnimatedUIKitImage(image: image, contentMode: contentMode)
            } else if displaysFailure {
                TemplateMediaUnavailablePlaceholder()
            }
        }
        .clipped()
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        let requestedURL = url
        resolvedURL = requestedURL
        didFail = false
        image = nil

        do {
            let loadedImage = try await TemplateImageRepository.shared.image(for: requestedURL)
            guard !Task.isCancelled, url == requestedURL else { return }
            image = loadedImage
        } catch {
            guard !Task.isCancelled, url == requestedURL else { return }
            didFail = true
        }
    }
}

private struct AnimatedUIKitImage: UIViewRepresentable {
    let image: UIImage
    let contentMode: UIView.ContentMode

    func makeUIView(context: Context) -> AnimatedImageContainerView {
        let container = AnimatedImageContainerView()
        container.imageView.contentMode = contentMode
        return container
    }

    func updateUIView(_ container: AnimatedImageContainerView, context: Context) {
        let imageView = container.imageView
        imageView.contentMode = contentMode
        guard imageView.image !== image else { return }
        imageView.stopAnimating()
        imageView.image = image
        if image.images != nil {
            imageView.startAnimating()
        }
    }

    static func dismantleUIView(_ container: AnimatedImageContainerView, coordinator: Void) {
        container.imageView.stopAnimating()
    }
}

private final class AnimatedImageContainerView: UIView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.clipsToBounds = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct HeroCarouselSkeleton: View {
    var cornerRadius: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.56),
                        AppPalette.surfaceEdge.opacity(0.14),
                        Color.white.opacity(0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 12) {
                    SkeletonBlock(
                        width: min(width * 0.54, 250),
                        height: 28,
                        cornerRadius: 9
                    )

                    SkeletonBlock(
                        width: min(width * 0.38, 176),
                        height: 18,
                        cornerRadius: 7
                    )

                    SkeletonBlock(
                        width: min(width * 0.66, 304),
                        height: 72,
                        cornerRadius: 18
                    )
                }
                .padding(.top, 34)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppPalette.surfaceEdge.opacity(0.10), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading carousel")
    }
}

private struct GuestHomeControls: View {
    let onLogin: () -> Void
    let onGift: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onLogin) {
                HStack(spacing: 4) {
                    Image("RewardsCreditToken")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)

                    Text("Free Use")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color(red: 1, green: 0.36, blue: 0.31), in: Capsule())
            }
            .accessibilityLabel("Free Use")

            Button(action: onGift) {
                AnimatedGiftIcon(size: 54)
                    .scaleEffect(0.7)
                    .frame(width: 38, height: 38)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hotScale: CGFloat = 0.78
    @State private var drawerProgress: CGFloat = 1

    init(_ label: String, size: Size) {
        self.label = label.uppercased()
        self.size = size
    }

    private var isHot: Bool { label == "HOT" }
    private var isNew: Bool { label == "NEW" }
    private var isHangingNewTag: Bool { size == .section && isNew }

    var body: some View {
        badgeArtwork
            .fixedSize()
            .compositingGroup()
            .scaleEffect(isHot ? hotScale : 1, anchor: .center)
            // NEW is revealed by a moving mask instead of horizontal scaling;
            // this keeps the cord, tag and lettering at their natural shape.
            .mask(alignment: .leading) {
                Rectangle()
                    .scaleEffect(x: isNew ? drawerProgress : 1, anchor: .leading)
            }
            .offset(x: isNew ? -8 * (1 - drawerProgress) : 0)
            .opacity(isNew ? min(1, drawerProgress * 3) : 1)
            .accessibilityLabel(label)
            .task(id: "\(label)-\(reduceMotion)") {
                resetAnimationState()
                guard !reduceMotion else { return }
                if isHot {
                    await runHotPulse()
                } else if isNew {
                    await runNewDrawer()
                }
            }
    }

    @ViewBuilder
    private var badgeArtwork: some View {
        if isHot {
            PulsingHotBadge(
                label: label,
                height: size.height,
                fontSize: size.fontSize,
                horizontalPadding: size.horizontalPadding
            )
        } else if isHangingNewTag {
            NewHangingTagBadge(
                label: label,
                height: size.height,
                fontSize: size.fontSize
            )
        } else {
            Text(label)
                .font(.system(size: size.fontSize, weight: .heavy))
                .foregroundStyle(.black)
                .padding(.horizontal, size.horizontalPadding)
                .frame(height: size.height)
                .background {
                    Capsule()
                        .fill(Color(red: 1.0, green: 0.76, blue: 0.03))
                }
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.34), lineWidth: 0.7)
                }
        }
    }

    @MainActor
    private func resetAnimationState() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            hotScale = reduceMotion ? 1 : 0.78
            drawerProgress = reduceMotion || !isNew ? 1 : 0
        }
    }

    @MainActor
    private func runHotPulse() async {
        while !Task.isCancelled {
            withAnimation(.easeOut(duration: 0.48)) { hotScale = 1.22 }
            try? await Task.sleep(nanoseconds: 480_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.52)) { hotScale = 0.78 }
            try? await Task.sleep(nanoseconds: 520_000_000)
        }
    }

    @MainActor
    private func runNewDrawer() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.42)) { drawerProgress = 1 }
            try? await Task.sleep(nanoseconds: 1_120_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeIn(duration: 0.32)) { drawerProgress = 0 }
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
    }
}

private struct PulsingHotBadge: View {
    let label: String
    let height: CGFloat
    let fontSize: CGFloat
    let horizontalPadding: CGFloat

    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding + 1)
            .frame(height: height)
            .background {
                HotPulseBadgeShape()
                    .fill(
                LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.22, blue: 0.18),
                                Color(red: 0.91, green: 0.06, blue: 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(
                color: Color(red: 0.78, green: 0.04, blue: 0.08).opacity(0.28),
                radius: 2,
                y: 1
            )
            .accessibilityHidden(true)
    }
}

private struct HotPulseBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = min(4.5, rect.height * 0.24)
        let radius = min(3, rect.height * 0.16)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + cut + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cut - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX - cut, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cut + radius, y: rect.minY),
            control: CGPoint(x: rect.minX + cut, y: rect.minY)
                )
        path.closeSubpath()
        return path
    }
}

private struct NewHangingTagBadge: View {
    let label: String
    let height: CGFloat
    let fontSize: CGFloat

    private var width: CGFloat { max(56, height * 2.8) }

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                let middleY = canvasSize.height / 2
                let bodyX = canvasSize.height * 0.52
                let tipDepth = canvasSize.height * 0.30
                let radius = min(5, canvasSize.height * 0.24)
                let bodyRect = CGRect(
                    x: bodyX + tipDepth,
                    y: 1,
                    width: canvasSize.width - bodyX - tipDepth,
                    height: canvasSize.height - 2
                )

                var tag = Path()
                tag.move(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY))
                tag.addLine(to: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.minY))
                tag.addQuadCurve(
                    to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY + radius),
                    control: CGPoint(x: bodyRect.maxX, y: bodyRect.minY)
                )
                tag.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - radius))
                tag.addQuadCurve(
                    to: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.maxY),
                    control: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY)
                )
                tag.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.maxY))
                tag.addLine(to: CGPoint(x: bodyX, y: middleY))
                tag.closeSubpath()
                context.fill(tag, with: .color(AppPalette.ink))

                let attachment = CGPoint(x: bodyRect.minX + 0.5, y: middleY)
                let loopRect = CGRect(
                    x: 1.5,
                    y: 3.5,
                    width: 8.5,
                    height: canvasSize.height - 7
                )
                let loop = Path(roundedRect: loopRect, cornerRadius: loopRect.width / 2)
                context.stroke(
                    loop,
                    with: .color(AppPalette.accent),
                    style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round)
                )

                var connector = Path()
                connector.move(to: CGPoint(x: loopRect.maxX - 0.5, y: middleY))
                connector.addLine(to: attachment)
                context.stroke(
                    connector,
                    with: .color(AppPalette.accent),
                    style: StrokeStyle(lineWidth: 1.55, lineCap: .round)
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: attachment.x - 1.35, y: attachment.y - 1.35, width: 2.7, height: 2.7)),
                    with: .color(AppPalette.accent)
                )
            }

            Text(label)
                .font(.system(size: fontSize, weight: .heavy))
                .foregroundStyle(.white)
                .offset(x: height * 0.39)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

private struct HomeQuickActionStrip: View {
    let actions: [HomeQuickAction]
    let isLoading: Bool
    let onSelect: (FixedFeature) -> Void

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let cardWidth = max(108, (proxy.size.width - 64) / 3)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        if isLoading {
                            ForEach(0..<3, id: \.self) { _ in
                                VStack(spacing: 7) {
                                    TemplateMediaLoadingPlaceholder()
                                        .frame(width: cardWidth, height: 66)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    Capsule()
                                        .fill(AppPalette.surfaceEdge.opacity(0.15))
                                        .frame(width: cardWidth * 0.68, height: 12)
                                }
                                .frame(width: cardWidth)
                                .accessibilityHidden(true)
                            }
                        } else {
                            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                                Button {
                                    onSelect(action.feature)
                                } label: {
                                    VStack(spacing: 7) {
                                        ZStack(alignment: .topTrailing) {
                                            TemplateMediaView(
                                                item: action.item,
                                                gravity: .resizeAspectFill,
                                                imageContentMode: .fit,
                                                fillsFitImageBackground: true
                                            )
                                                .frame(width: cardWidth, height: 66)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                            if let badge = TemplateBadgePolicy.badge(for: action.item, at: index, on: .home) {
                                                AnimatedFeatureBadge(badge, size: .card)
                                                    .offset(x: -4, y: 4)
                                            }
                                        }
                                        Text(action.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppPalette.ink)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.72)
                                    }
                                    .frame(width: cardWidth)
                                }
                                .buttonStyle(TemplatePressStyle())
                                .accessibilityLabel(action.title)
                                .accessibilityIdentifier("fixed-feature-\(action.feature.id)")
                            }
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

                if let firstItem = section.items.first {
                    Button {
                        onSelect(firstItem)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppPalette.ink.opacity(0.78))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(section.title)")
                    .accessibilityIdentifier("open-section-\(section.id)")
                }
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
    var portraitWidth: CGFloat = 110
    let action: () -> Void

    private var cardSize: CGSize {
        item.orientation == .landscape
            ? CGSize(width: 174, height: 116)
            : CGSize(width: portraitWidth, height: 180)
    }

    init(item: TemplateItem, portraitWidth: CGFloat = 110, action: @escaping () -> Void) {
        self.item = item
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

            }
            .frame(width: cardSize.width, height: cardSize.height)
            .overlay(alignment: .bottom) {
                Text(item.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
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
    var imageContentMode: ContentMode = .fill
    var fillsFitImageBackground = false
    var aspectFitVideoBackgroundColor: UIColor = .black
    var imageMaxPixelSize = 960
    var playsVideo = true
    var showsLoadingPlaceholder = true

    @State private var resolvedPosterIdentity: String?

    private var posterIdentity: String? {
        if let comparison = item.comparisonCover {
            return "comparison|\(comparison.beforeURL.absoluteString)|\(comparison.afterURL.absoluteString)"
        }
        return item.coverImageURL.map { "image|\($0.absoluteString)" }
    }

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
            if showsLoadingPlaceholder {
                TemplateMediaLoadingPlaceholder()
            }

            if let comparisonCover = item.comparisonCover {
                TemplateComparisonView(
                    cover: comparisonCover,
                    imageContentMode: imageContentMode,
                    maxPixelSize: imageMaxPixelSize,
                    onMediaResolved: { _ in resolvedPosterIdentity = posterIdentity }
                )
            } else if let coverImageURL = item.coverImageURL {
                RemoteTemplateImage(
                    url: coverImageURL,
                    imageContentMode: imageContentMode,
                    fillsFitBackground: fillsFitImageBackground,
                    maxPixelSize: imageMaxPixelSize,
                    onResolution: { _ in resolvedPosterIdentity = posterIdentity }
                )
            } else if !item.imageName.isEmpty {
                if imageContentMode == .fit {
                    GeometryReader { proxy in
                        ZStack {
                            if fillsFitImageBackground {
                                Image(item.imageName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .clipped()
                                    .blur(radius: 9)

                                Color.black.opacity(0.10)
                            }

                            Image(item.imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    }
                } else {
                    Image(item.imageName)
                        .resizable()
                        .scaledToFill()
                }
            }

            // Image filters can reuse catalog entries that also have a legacy
            // video preview name. Their cover must remain a still image.
            if playsVideo,
               item.generationKind == .video,
               posterIdentity == nil || resolvedPosterIdentity == posterIdentity {
                if let coverVideoURL = item.coverVideoURL {
                    RemoteLoopingVideoView(
                        url: coverVideoURL,
                        videoGravity: effectiveGravity,
                        aspectFitBackgroundColor: aspectFitVideoBackgroundColor
                    )
                        .allowsHitTesting(false)
                } else if let videoName = item.videoName {
                    LoopingVideoView(
                        resourceName: videoName,
                        videoGravity: effectiveGravity,
                        aspectFitBackgroundColor: aspectFitVideoBackgroundColor
                    )
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
    var maxPixelSize = 960
    var onMediaResolved: (Bool) -> Void = { _ in }

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
                            .overlay {
                                HorizontalComparisonDragSurface(
                                    onChanged: { locationX in
                                        draggedProgress = clampedProgress(locationX / max(width, 1))
                                    },
                                    onEnded: {
                                        draggedProgress = nil
                                    }
                                )
                                .accessibilityHidden(true)
                            }
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
            RemoteTemplateImage(
                url: cover.afterURL,
                imageContentMode: imageContentMode,
                maxPixelSize: maxPixelSize,
                onResolution: onMediaResolved
            )
                .frame(width: width, height: height)

            RemoteTemplateImage(
                url: cover.beforeURL,
                imageContentMode: imageContentMode,
                maxPixelSize: maxPixelSize,
                onResolution: onMediaResolved
            )
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

/// Bridges the comparison scrubber to UIKit so a vertical drag can fail before
/// it competes with the detail screen's vertical paging scroll view. A SwiftUI
/// `DragGesture` enters recognition for every direction; ignoring vertical
/// values in `onChanged` does not return that gesture to the parent scroll view.
private struct HorizontalComparisonDragSurface: UIViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false

        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        panGesture.cancelsTouchesInView = false
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded: () -> Void

        init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping () -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }

            switch gesture.state {
            case .began, .changed:
                onChanged(gesture.location(in: view).x)
            case .ended, .cancelled, .failed:
                onEnded()
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
                return true
            }

            let velocity = panGesture.velocity(in: panGesture.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

struct RemoteTemplateImage: View {
    let url: URL
    var imageContentMode: ContentMode = .fill
    var fillsFitBackground = false
    var maxPixelSize = 960
    var onResolution: (Bool) -> Void = { _ in }

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var resolvedRequestID: RequestID?

    private struct RequestID: Hashable {
        let url: URL
        let maxPixelSize: Int
    }

    private var requestID: RequestID {
        RequestID(url: url, maxPixelSize: maxPixelSize)
    }

    private var displayedImage: UIImage? {
        if resolvedRequestID == requestID, let image {
            return image
        }
        return TemplateImageMemoryCache.shared.image(for: url, maxPixelSize: maxPixelSize)
    }

    private var displaysFailure: Bool {
        resolvedRequestID == requestID && didFail
    }

    var body: some View {
        Group {
            if let image = displayedImage {
                if imageContentMode == .fit {
                    GeometryReader { proxy in
                        ZStack {
                            if fillsFitBackground {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .clipped()
                                    .blur(radius: 9)

                                Color.black.opacity(0.10)
                            }

                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    }
                } else {
                    ZStack {
                        // A CMS cover can legitimately contain alpha (for
                        // example a product-box cutout). Once the image is
                        // resolved, do not let the gold loading skeleton show
                        // through those pixels or change between card/detail.
                        Color.black

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
            } else if displaysFailure {
                TemplateMediaUnavailablePlaceholder()
            } else {
                Color.clear
            }
        }
        .task(id: requestID) {
            await loadImage(for: requestID)
        }
    }

    private func loadImage(for request: RequestID) async {
        resolvedRequestID = request
        didFail = false
        image = nil

        if let cachedImage = TemplateImageMemoryCache.shared.image(
            for: request.url,
            maxPixelSize: request.maxPixelSize
        ) {
            TemplateMediaMetrics.shared.record(.memory, media: .image)
            image = cachedImage
            TemplateMediaMetrics.shared.markPosterDisplayed(for: request.url)
            onResolution(true)
            return
        }

        do {
            let loadedImage = try await TemplateImageRepository.shared.image(
                for: request.url,
                maxPixelSize: request.maxPixelSize
            )
            guard !Task.isCancelled, requestID == request else { return }
            image = loadedImage
            TemplateMediaMetrics.shared.markPosterDisplayed(for: request.url)
            onResolution(true)
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            didFail = true
            onResolution(false)
        }
    }
}

/// Shared phase-style image loader for generated results, avatars and history
/// thumbnails. Unlike AsyncImage, every call participates in the same memory,
/// disk and in-flight request cache as template posters.
struct CachedRemoteImage<Content: View, Placeholder: View, Failure: View>: View {
    let url: URL
    private let content: (UIImage) -> Content
    private let placeholder: () -> Placeholder
    private let failure: () -> Failure

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var resolvedURL: URL?

    private var displayedImage: UIImage? {
        if resolvedURL == url, let image {
            return image
        }
        return TemplateImageMemoryCache.shared.image(for: url)
    }

    private var displaysFailure: Bool {
        resolvedURL == url && didFail
    }

    init(
        url: URL,
        @ViewBuilder content: @escaping (UIImage) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            if let image = displayedImage {
                content(image)
            } else if displaysFailure {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            let requestedURL = url
            resolvedURL = requestedURL
            didFail = false
            image = nil
            if let cachedImage = TemplateImageMemoryCache.shared.image(for: requestedURL) {
                TemplateMediaMetrics.shared.record(.memory, media: .image)
                image = cachedImage
                return
            }
            do {
                let loadedImage = try await TemplateImageRepository.shared.image(for: requestedURL)
                guard !Task.isCancelled, url == requestedURL else { return }
                image = loadedImage
            } catch {
                guard !Task.isCancelled, url == requestedURL else { return }
                didFail = true
            }
        }
    }
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
    let actions: [HomeQuickAction]
    let containerWidth: CGFloat
    @Binding var selection: FixedFeature?

    private var columns: [GridItem] {
        actions.map { _ in
            GridItem(.flexible(minimum: 0), spacing: 0)
        }
    }

    var body: some View {
        let stripWidth = max(containerWidth - 36, 0)

        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(actions) { action in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { selection = action.feature }
                } label: {
                    Text(action.title)
                        .font(.system(size: 16, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(selection == action.feature ? .white : AppPalette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.66)
                        .allowsTightening(true)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background {
                            if selection == action.feature {
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
                .accessibilityAddTraits(selection == action.feature ? .isSelected : [])
                .accessibilityIdentifier("video-mode-\(action.feature.id)")
            }
        }
        .frame(width: stripWidth)
        .frame(width: containerWidth)
        .padding(.top, -6)
        .onChange(of: actions.map(\.feature), initial: true) { _, features in
            guard let firstFeature = features.first else {
                selection = nil
                return
            }
            if let selection, features.contains(selection) { return }
            selection = firstFeature
        }
    }
}

private struct VideoModeHero: View {
    let action: HomeQuickAction
    let containerWidth: CGFloat
    let onSelect: (FixedFeature) -> Void

    var body: some View {
        let heroWidth = max(containerWidth - 40, 0)

        ZStack(alignment: .bottomTrailing) {
            Button { onSelect(action.feature) } label: {
                ZStack {
                    TemplateMediaView(item: action.item, gravity: .resizeAspectFill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.30)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("video-mode-hero-\(action.feature.id)")

            Button { onSelect(action.feature) } label: {
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
            .accessibilityIdentifier("video-mode-try-now-\(action.feature.id)")
            .padding(.trailing, 20)
            .padding(.bottom, 15)
        }
        .frame(width: heroWidth, height: 219)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(width: containerWidth)
        .accessibilityLabel("Try \(action.feature.title)")
        .id(action.feature)
        .transition(.opacity)
    }
}
