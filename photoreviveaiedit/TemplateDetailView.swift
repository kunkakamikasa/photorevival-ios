import AVFoundation
import SwiftUI

struct TemplateDetailView: View {
    let item: TemplateItem
    let detailItems: [TemplateItem]
    let configuredTryNowItem: TemplateItem?
    let configuredTryNowItems: [TemplateItem]?
    let creationItemsProvider: ((TemplateItem) -> [TemplateItem])?
    let recommendationItemsProvider: ((TemplateItem) -> [TemplateItem])?
    let photoToVideoGenerationTarget: FeatureGenerationTarget?
    let creditPricing: AppCreditPricing
    @Binding var credits: Int
    let onClose: () -> Void
    @State private var selectedID: String?
    @State private var creationLaunch: TemplateCreationLaunch?
    @AppStorage("hasSeenTemplateDetailSwipeHint") private var hasSeenSwipeHint = false
    @State private var showSwipeHint = false

    init(
        item: TemplateItem,
        detailItems: [TemplateItem]? = nil,
        tryNowItem: TemplateItem? = nil,
        tryNowItems: [TemplateItem]? = nil,
        creationItemsProvider: ((TemplateItem) -> [TemplateItem])? = nil,
        recommendationItemsProvider: ((TemplateItem) -> [TemplateItem])? = nil,
        photoToVideoGenerationTarget: FeatureGenerationTarget? = nil,
        creditPricing: AppCreditPricing = .defaultValue,
        credits: Binding<Int>,
        onClose: @escaping () -> Void
    ) {
        self.item = item
        let sourceItems = detailItems?.isEmpty == false
            ? detailItems!
            : TemplateCatalog.detailItems(for: item)

        // Put the tapped item first so the correct page is visible even before
        // ScrollViewReader has completed its first layout pass. This matters on
        // a cold launch, where scrollTo can otherwise be ignored for one frame.
        if let selectedIndex = sourceItems.firstIndex(where: { $0.id == item.id }) {
            let remainingItems = Array(sourceItems.dropFirst(selectedIndex + 1))
                + Array(sourceItems.prefix(selectedIndex))
            self.detailItems = [item] + remainingItems
        } else {
            self.detailItems = [item] + sourceItems.filter { $0.id != item.id }
        }
        self.configuredTryNowItem = tryNowItem
        self.configuredTryNowItems = tryNowItems
        self.creationItemsProvider = creationItemsProvider
        self.recommendationItemsProvider = recommendationItemsProvider
        self.photoToVideoGenerationTarget = photoToVideoGenerationTarget
        self.creditPricing = creditPricing
        self._credits = credits
        self.onClose = onClose
        self._selectedID = State(initialValue: item.id)
    }

    var body: some View {
        ZStack {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(detailItems) { detailItem in
                            TemplateDetailPage(
                                item: detailItem,
                                playsVideo: selectedID == detailItem.id,
                                onClose: onClose,
                                onTry: {
                                    let creationTemplate: TemplateItem
                                    if detailItem.id == item.id,
                                       let configuredTryNowItem {
                                        creationTemplate = configuredTryNowItem
                                        creationLaunch = TemplateCreationLaunch(
                                            template: configuredTryNowItem,
                                            templates: configuredTryNowItems ?? [configuredTryNowItem]
                                        )
                                    } else {
                                        creationTemplate = detailItem
                                        creationLaunch = TemplateCreationLaunch(
                                            template: detailItem,
                                            templates: creationTemplates(for: detailItem)
                                        )
                                    }
                                    AppAnalytics.templateTryNow(creationTemplate)
                                }
                            )
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(detailItem.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selectedID)
                .scrollIndicators(.hidden)
                .background(Color.black)
                .ignoresSafeArea()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard abs(value.translation.height) > abs(value.translation.width) else { return }
                            dismissSwipeHint()
                        }
                )
                .onAppear {
                    // A detail page must open on the exact cover that was tapped.
                    selectedID = item.id
                    scrollProxy.scrollTo(item.id, anchor: .center)
                }
            }

            if showSwipeHint {
                Color.black.opacity(0.50)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                SwipeHintView()
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Swipe up or down to browse templates")
                    .accessibilityIdentifier("template-swipe-hint")
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $creationLaunch) { launch in
            if launch.template.generationKind == .image {
                ImageGenerationUploadView(
                    template: launch.template,
                    creditPricing: creditPricing,
                    credits: $credits,
                    recommendationItems: recommendationItemsProvider?(launch.template) ?? [],
                    photoToVideoGenerationTarget: photoToVideoGenerationTarget
                )
            } else {
                CreateFlowView(
                    template: launch.template,
                    templates: launch.templates,
                    creditPricing: creditPricing,
                    credits: $credits
                )
            }
        }
        .onAppear {
            presentSwipeHintIfNeeded()
            AppAnalytics.screen("template_detail", className: "TemplateDetailView")
            AppAnalytics.templateDetailViewed(item)
        }
        .onChange(of: selectedID) { _, newID in
            guard newID != item.id else { return }
            dismissSwipeHint()
            if let newID,
               let selectedItem = detailItems.first(where: { $0.id == newID }) {
                AppAnalytics.templateDetailViewed(selectedItem)
            }
        }
    }

    private func presentSwipeHintIfNeeded() {
        guard detailItems.count > 1 else { return }
        guard !hasSeenSwipeHint || isSwipeHintForced else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            showSwipeHint = true
        }

        guard !isSwipeHintForced else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            dismissSwipeHint()
        }
    }

    private func dismissSwipeHint() {
        guard showSwipeHint else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            showSwipeHint = false
        }
        if !isSwipeHintForced {
            hasSeenSwipeHint = true
        }
    }

    private var isSwipeHintForced: Bool {
        ProcessInfo.processInfo.arguments.contains("-forceTemplateSwipeHint")
    }

    private func creationTemplates(for detailItem: TemplateItem) -> [TemplateItem] {
        if let creationItemsProvider {
            return creationItemsProvider(detailItem)
        }

        guard let groupID = detailItem.detailGroupID else { return [detailItem] }

        let groupItems = detailItems.filter {
            $0.detailGroupID == groupID
                && $0.generationKind == detailItem.generationKind
        }
        return groupItems.isEmpty ? [detailItem] : groupItems
    }
}

struct TemplateCreationLaunch: Identifiable {
    let template: TemplateItem
    let templates: [TemplateItem]

    var id: String { template.id }

    init(template: TemplateItem, templates: [TemplateItem]) {
        self.template = template
        self.templates = templates.contains(where: { $0.id == template.id })
            ? templates
            : [template] + templates
    }
}

private struct TemplateDetailPage: View {
    let item: TemplateItem
    let playsVideo: Bool
    let onClose: () -> Void
    let onTry: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if let comparisonCover = item.comparisonCover {
                    TemplateComparisonView(
                        cover: comparisonCover,
                        allowsInteraction: true,
                        imageContentMode: .fill,
                        maxPixelSize: 1_920
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                } else if item.orientation == .landscape {
                    TemplateMediaView(
                        item: item,
                        gravity: .resizeAspect,
                        imageMaxPixelSize: 1_920,
                        playsVideo: playsVideo
                    )
                        .frame(width: proxy.size.width, height: proxy.size.width / item.orientation.aspectRatio)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.47)
                } else {
                    TemplateMediaView(
                        item: item,
                        gravity: .resizeAspectFill,
                        imageMaxPixelSize: 1_920,
                        playsVideo: playsVideo
                    )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(item.orientation == .portrait ? 0.82 : 0.50)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack {
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.34), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
                        }
                        .accessibilityLabel("Close detail")
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, proxy.safeAreaInsets.top + 64)

                    Spacer()

                    VStack(alignment: .leading, spacing: 14) {
                        if item.orientation == .portrait {
                            Text(item.title)
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: onTry) {
                            Text("Try Now")
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 64)
                                .background(.black.opacity(0.55), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Try \(item.title)")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 26)
                }
            }
        }
    }
}

private struct SwipeHintView: View {
    @State private var handOffset: CGFloat = 16

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.22))
                    .frame(width: 9, height: 108)
                    .offset(x: -8, y: 6)

                Circle()
                    .fill(.white.opacity(0.70))
                    .frame(width: 30, height: 30)
                    .shadow(color: .white.opacity(0.38), radius: 7)
                    .offset(x: -8, y: -30)

                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.90), radius: 7)
                    .shadow(color: .white.opacity(0.55), radius: 18)
                    .rotationEffect(.degrees(-25))
                    .scaleEffect(x: 0.92, y: 0.74)
                    .offset(x: 8, y: handOffset - 40)
            }
            .frame(width: 220, height: 140)

            Text("Swipe up or down to explore\nmore templates")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .offset(y: -4)
        }
        .offset(y: -18)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
                handOffset = -16
            }
        }
    }
}
