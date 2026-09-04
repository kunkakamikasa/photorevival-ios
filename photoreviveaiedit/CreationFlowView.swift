import AVFoundation
import SwiftUI
import UIKit

private enum CreateFlowCropTarget: Identifiable {
    case source
    case videoSlot(Int)

    var id: String {
        switch self {
        case .source: "source"
        case let .videoSlot(index): "video-slot-\(index)"
        }
    }
}

private enum CreateFlowPhotoSelectionTarget: Identifiable {
    case source
    case videoSlots

    var id: String {
        switch self {
        case .source: "source"
        case .videoSlots: "video-slots"
        }
    }
}

private enum PendingVideoGenerationEndpoint {
    case imageToVideo
    case textToVideo
}

private struct PendingVideoGenerationRequest {
    let endpoint: PendingVideoGenerationEndpoint
    let itemID: String
    let images: [UIImage]
    let prompt: String?
    let appVersion: String?
    let options: PhotoReviveVideoGenerationOptions

    @MainActor
    func submit() async throws -> PhotoReviveVideoGenerationSubmission {
        switch endpoint {
        case .imageToVideo:
            var imageURLs: [String] = []
            for image in images {
                guard let imageData = image.jpegData(compressionQuality: 0.90) else {
                    throw PhotoReviveAPIError.invalidResponse
                }
                let imageURL = try await PhotoReviveAPIClient.shared.uploadGenerationImage(imageData)
                imageURLs.append(imageURL)
            }

            return try await PhotoReviveAPIClient.shared.createImageToVideo(
                itemID: itemID,
                imageURLs: imageURLs,
                prompt: prompt,
                appVersion: appVersion,
                options: options
            )
        case .textToVideo:
            return try await PhotoReviveAPIClient.shared.createTextToVideo(
                itemID: itemID,
                prompt: prompt,
                options: options
            )
        }
    }
}

private enum PendingImageGenerationEndpoint {
    case imageToImage
    case textToImage
}

/// Captures everything needed to submit an image job before the progress
/// screen is presented. Keeping the slow JPEG encoding, upload, and API call
/// out of the upload view lets the app move to My Creations immediately.
private struct PendingImageGenerationRequest {
    let endpoint: PendingImageGenerationEndpoint
    let itemID: String
    let images: [UIImage]
    let prompt: String?
    let options: PhotoReviveImageGenerationOptions

    @MainActor
    func submit() async throws -> PhotoReviveImageGenerationSubmission {
        switch endpoint {
        case .imageToImage:
            var imageURLs: [String] = []
            for image in images {
                guard let imageData = image.jpegData(compressionQuality: 0.90) else {
                    throw PhotoReviveAPIError.invalidResponse
                }
                imageURLs.append(
                    try await PhotoReviveAPIClient.shared.uploadGenerationImage(imageData)
                )
            }

            return try await PhotoReviveAPIClient.shared.createImageToImage(
                itemID: itemID,
                imageURLs: imageURLs,
                prompt: prompt,
                options: options
            )
        case .textToImage:
            return try await PhotoReviveAPIClient.shared.createTextToImage(
                itemID: itemID,
                prompt: prompt,
                options: options
            )
        }
    }
}

/// Sizes the prompt-based video editor from the actual space below the
/// navigation bar. The three flexible regions shrink together on shorter
/// iPhones, while the settings and primary action retain comfortable tap
/// targets. Their computed total never exceeds the available viewport.
private struct GuidedVideoEditorLayout {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let sectionSpacing: CGFloat
    let templateSpacing: CGFloat
    let uploadHeight: CGFloat
    let uploadWidth: CGFloat
    let promptHeight: CGFloat
    let thumbnailHeight: CGFloat
    let thumbnailWidth: CGFloat
    let templateChooserHeight: CGFloat
    let usesCompactControls: Bool

    var buttonHeight: CGFloat { 61 }

    init(viewportSize: CGSize) {
        let height = max(0, viewportSize.height)
        usesCompactControls = height < 700 || viewportSize.width < 375
        horizontalPadding = viewportSize.width < 375 ? 16 : 20
        topPadding = 6
        bottomPadding = 8
        sectionSpacing = height < 650 ? 7 : (height < 760 ? 9 : 12)
        templateSpacing = usesCompactControls ? 6 : 10

        let settingsHeight: CGFloat = 55
        let templateTitleHeight: CGFloat = usesCompactControls ? 22 : 27
        let fixedHeight = topPadding
            + bottomPadding
            + sectionSpacing * 4
            + settingsHeight
            + 61
            + templateTitleHeight
            + templateSpacing
        let flexibleHeight = max(0, height - fixedHeight)

        let preferred = (upload: CGFloat(214), prompt: CGFloat(150), thumbnail: CGFloat(214))
        let minimum = (upload: CGFloat(124), prompt: CGFloat(96), thumbnail: CGFloat(110))
        let preferredTotal = preferred.upload + preferred.prompt + preferred.thumbnail
        let minimumTotal = minimum.upload + minimum.prompt + minimum.thumbnail

        if flexibleHeight >= preferredTotal {
            uploadHeight = preferred.upload
            promptHeight = preferred.prompt
            thumbnailHeight = preferred.thumbnail
        } else if flexibleHeight >= minimumTotal {
            let progress = (flexibleHeight - minimumTotal) / (preferredTotal - minimumTotal)
            uploadHeight = minimum.upload + (preferred.upload - minimum.upload) * progress
            promptHeight = minimum.prompt + (preferred.prompt - minimum.prompt) * progress
            thumbnailHeight = minimum.thumbnail + (preferred.thumbnail - minimum.thumbnail) * progress
        } else {
            let scale = flexibleHeight / minimumTotal
            uploadHeight = minimum.upload * scale
            promptHeight = minimum.prompt * scale
            thumbnailHeight = minimum.thumbnail * scale
        }

        uploadWidth = min(166, uploadHeight * 0.76)
        thumbnailWidth = min(158, thumbnailHeight * 0.74)
        templateChooserHeight = templateTitleHeight + templateSpacing + thumbnailHeight
    }
}

/// Distributes a limited vertical budget across the flexible regions on an
/// upload page. Preferred sizes are retained on taller phones; on shorter
/// phones every region contracts together so no single card pushes another
/// control below the fixed primary action.
struct UploadPageFlexibleLayout {
    static func fittedSizes(
        availableHeight: CGFloat,
        preferred: [CGFloat],
        minimum: [CGFloat]
    ) -> [CGFloat] {
        guard preferred.count == minimum.count, !preferred.isEmpty else { return [] }

        let availableHeight = max(0, availableHeight)
        let preferredTotal = preferred.reduce(0, +)
        let minimumTotal = minimum.reduce(0, +)

        if availableHeight >= preferredTotal {
            return preferred
        }

        if availableHeight >= minimumTotal,
           preferredTotal > minimumTotal {
            let progress = (availableHeight - minimumTotal)
                / (preferredTotal - minimumTotal)
            return zip(minimum, preferred).map { minimumSize, preferredSize in
                minimumSize + (preferredSize - minimumSize) * progress
            }
        }

        guard minimumTotal > 0 else {
            return Array(repeating: 0, count: preferred.count)
        }
        let scale = availableHeight / minimumTotal
        return minimum.map { $0 * scale }
    }
}

/// Keeps one or two upload cards inside the available width, while preserving
/// a readable card width for three or more inputs and letting that row scroll
/// horizontally. This never changes the row's vertical height.
struct HorizontalUploadStripLayout {
    let itemWidth: CGFloat
    let contentWidth: CGFloat
    let scrollsHorizontally: Bool

    init(
        viewportWidth: CGFloat,
        itemCount: Int,
        preferredItemWidth: CGFloat,
        minimumScrollableItemWidth: CGFloat = 118,
        spacing: CGFloat = 14
    ) {
        let viewportWidth = max(0, viewportWidth)
        let itemCount = max(1, itemCount)
        scrollsHorizontally = itemCount >= 3

        if scrollsHorizontally {
            itemWidth = max(minimumScrollableItemWidth, preferredItemWidth)
        } else {
            let availableWidth = max(0, viewportWidth - spacing * CGFloat(itemCount - 1))
            itemWidth = min(preferredItemWidth, availableWidth / CGFloat(itemCount))
        }

        contentWidth = itemWidth * CGFloat(itemCount)
            + spacing * CGFloat(itemCount - 1)
    }
}

struct FixedPhotoUploadLayout {
    let spacing: CGFloat
    let titleHeight: CGFloat
    let titleFontSize: CGFloat
    let previewHeight: CGFloat
    let tipImageHeight: CGFloat
    let tipSpacing: CGFloat
    let tipIconSize: CGFloat

    init(viewportSize: CGSize) {
        let height = max(0, viewportSize.height)
        let compact = height < 600
        spacing = compact ? 10 : 14
        titleHeight = compact ? 25 : 28
        titleFontSize = compact ? 20 : 22
        tipSpacing = compact ? 6 : 8
        tipIconSize = compact ? 21 : 25
        tipImageHeight = min(compact ? 64 : 76, max(38, height * 0.11))

        let fixedHeight = spacing * 2
            + titleHeight
            + tipImageHeight
            + tipSpacing
            + tipIconSize
        let idealPreviewHeight = max(0, viewportSize.width) / (1168.0 / 1560.0)
        previewHeight = min(idealPreviewHeight, max(0, height - fixedHeight))
    }

    var occupiedHeight: CGFloat {
        previewHeight
            + spacing * 2
            + titleHeight
            + tipImageHeight
            + tipSpacing
            + tipIconSize
    }
}

struct FixedVideoUploadLayout {
    let spacing: CGFloat
    let tabsHeight: CGFloat = 46
    let previewHeight: CGFloat
    let promptHeight: CGFloat
    let settingsHeight: CGFloat = 48

    init(viewportSize: CGSize) {
        spacing = viewportSize.height < 600 ? 8 : 12
        let fixedHeight = tabsHeight + settingsHeight + spacing * 3
        let previewPreferred = min(270, max(0, viewportSize.width) / UploadPreviewLayout.aspectRatio)
        let fitted = UploadPageFlexibleLayout.fittedSizes(
            availableHeight: viewportSize.height - fixedHeight,
            preferred: [previewPreferred, 220],
            minimum: [120, 90]
        )
        previewHeight = fitted[0]
        promptHeight = fitted[1]
    }

    var occupiedHeight: CGFloat {
        tabsHeight + previewHeight + promptHeight + settingsHeight + spacing * 3
    }
}

struct ImageTemplateUploadLayout {
    let spacing: CGFloat
    let previewHeight: CGFloat
    let titleHeight: CGFloat
    let uploadHeight: CGFloat
    let settingsHeight: CGFloat = 48

    init(viewportSize: CGSize) {
        spacing = viewportSize.height < 600 ? 8 : 12
        titleHeight = viewportSize.height < 600 ? 26 : 29
        let fixedHeight = titleHeight + settingsHeight + spacing * 3
        let fitted = UploadPageFlexibleLayout.fittedSizes(
            availableHeight: viewportSize.height - fixedHeight,
            preferred: [302, 188],
            minimum: [140, 100]
        )
        previewHeight = fitted[0]
        uploadHeight = fitted[1]
    }

    var occupiedHeight: CGFloat {
        previewHeight + titleHeight + uploadHeight + settingsHeight + spacing * 3
    }
}

struct FixedAIImageUploadLayout {
    let spacing: CGFloat
    let tabsHeight: CGFloat
    let titleHeight: CGFloat
    let uploadHeight: CGFloat
    let promptHeight: CGFloat
    let settingsHeight: CGFloat = 48

    init(viewportSize: CGSize, showsTabs: Bool, includesUploads: Bool) {
        spacing = viewportSize.height < 600 ? 8 : 12
        tabsHeight = showsTabs ? 46 : 0
        titleHeight = includesUploads ? (viewportSize.height < 600 ? 24 : 27) : 0

        let visibleSections = 2
            + (showsTabs ? 1 : 0)
            + (includesUploads ? 2 : 0)
        let spacingCount = max(0, visibleSections - 1)
        let fixedHeight = tabsHeight
            + titleHeight
            + settingsHeight
            + spacing * CGFloat(spacingCount)

        if includesUploads {
            let fitted = UploadPageFlexibleLayout.fittedSizes(
                availableHeight: viewportSize.height - fixedHeight,
                preferred: [218, 220],
                minimum: [110, 100]
            )
            uploadHeight = fitted[0]
            promptHeight = fitted[1]
        } else {
            uploadHeight = 0
            promptHeight = min(280, max(0, viewportSize.height - fixedHeight))
        }
    }

    var occupiedHeight: CGFloat {
        let sectionCount = 2
            + (tabsHeight > 0 ? 1 : 0)
            + (uploadHeight > 0 ? 2 : 0)
        return tabsHeight
            + titleHeight
            + uploadHeight
            + promptHeight
            + settingsHeight
            + spacing * CGFloat(max(0, sectionCount - 1))
    }
}

struct CreateFlowView: View {
    let template: TemplateItem?
    let templates: [TemplateItem]?
    let creditPricing: AppCreditPricing
    @Binding var credits: Int

    @Environment(\.dismiss) private var dismiss
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @State private var activeTemplate: TemplateItem?
    @State private var selectedImage: UIImage?
    @State private var selectedVideoImages: [UIImage?]
    @State private var prompt: String
    @State private var showOptions = false
    @State private var showCredits = false
    @State private var notice: CreationNotice?
    @State private var isCreating = false
    @State private var soundEnabled = false
    @State private var multiShotEnabled = false
    @State private var duration = "5s"
    @State private var videoResolution = "480p"
    @State private var imageResolution = PhotoReviveImageGenerationOptions.providerDefaultResolution
    @State private var ratio = "9:16"
    @State private var outputCount = "1"
    @State private var showGenerationFlow = false
    @State private var cropTarget: CreateFlowCropTarget?
    @State private var photoSelectionTarget: CreateFlowPhotoSelectionTarget?
    @State private var pendingVideoGeneration: PendingVideoGenerationRequest?
    @State private var generationError: String?
    @State private var showLogin = false
    @State private var pendingLoginAction: (() -> Void)?

    init(
        template: TemplateItem?,
        templates: [TemplateItem]? = nil,
        creditPricing: AppCreditPricing = .defaultValue,
        credits: Binding<Int>
    ) {
        self.template = template
        self.templates = templates
        self.creditPricing = creditPricing
        _credits = credits
        _activeTemplate = State(initialValue: template)
        _selectedVideoImages = State(initialValue: Array(repeating: nil, count: max(1, template?.imageUploadCount ?? 1)))
        _prompt = State(initialValue: CreationFlowConfiguration(
            template: template,
            templateOptions: templates
        ).prompt)
        _soundEnabled = State(initialValue: creditPricing.defaultVideoSound)
        _multiShotEnabled = State(initialValue: creditPricing.defaultVideoMultiShot)
        _duration = State(initialValue: "\(creditPricing.videoDefaultDurationSeconds)s")
        _videoResolution = State(initialValue: creditPricing.defaultVideoResolution)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperTextureBackground()

                if flow.family == .videoNoPrompt {
                    GeometryReader { proxy in
                        noPromptVideoEditor(viewportHeight: proxy.size.height)
                    }
                } else if flow.family == .videoPrompt {
                    GeometryReader { proxy in
                        guidedVideoEditor(viewportSize: proxy.size)
                    }
                } else {
                    GeometryReader { proxy in
                        if flow.family == .image {
                            imageTemplateEditor(viewportSize: proxy.size)
                        } else {
                            standardVideoEditor(viewportSize: proxy.size)
                        }
                    }
                }
            }
            .navigationTitle(flow.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Close creation editor")
                }

                if flow.showsHelp {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            notice = .help
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel("Creation help")
                    }
                }
            }
        }
        .tint(AppPalette.accent)
        .preferredColorScheme(.light)
        .onAppear {
            AppAnalytics.screen("generation_editor", className: "CreateFlowView")
        }
#if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-showGeneratedVideoPreview") else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            showGenerationFlow = true
        }
#endif
        .sheet(item: $photoSelectionTarget) { target in
            PhotoSelectionSheet(
                maximumSelectionCount: target == .source ? 1 : flow.imageUploadCount
            ) { images in
                applySelectedPhotos(images, to: target)
            }
            .presentationDetents([.fraction(0.73), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(30)
        }
        .sheet(isPresented: $showOptions) {
            GenerationOptionsSheet(
                isImageFlow: flow.isImageFlow,
                videoCapabilities: videoCapabilities,
                imageCapabilities: imageCapabilities,
                soundEnabled: $soundEnabled,
                multiShotEnabled: $multiShotEnabled,
                duration: $duration,
                videoResolution: $videoResolution,
                imageResolution: $imageResolution,
                ratio: $ratio,
                outputCount: $outputCount
            )
            .presentationDetents([.fraction(flow.isImageFlow ? 0.60 : 0.64)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showCredits) {
            CreditCenterView(credits: $credits)
        }
        .fullScreenCover(isPresented: $showGenerationFlow) {
            if let pendingVideoGeneration {
                VideoGenerationFlowView(
                    title: flow.title,
                    templateTitle: activeTemplate?.title ?? template?.title ?? "Generated Video",
                    videoName: activeTemplate?.videoName ?? template?.videoName,
                    template: activeTemplate ?? template,
                    loadingPreviewImage: pendingVideoGeneration.images.first,
                    submissionAction: {
                        try await pendingVideoGeneration.submit()
                    },
                    onSubmission: { submission in
                        credits = submission.creditsBalance
                    },
                    onRegenerate: closeGenerationFlow,
                    onClose: closeGenerationFlow
                )
            } else {
                VideoGenerationFlowView(
                    title: flow.title,
                    templateTitle: activeTemplate?.title ?? template?.title ?? "Generated Video",
                    videoName: activeTemplate?.videoName ?? template?.videoName,
                    template: activeTemplate ?? template,
                    onRegenerate: closeGenerationFlow,
                    onClose: closeGenerationFlow
                )
            }
        }
        .fullScreenCover(item: $cropTarget) { target in
            switch target {
            case .source:
                if let selectedImage {
                    FeaturePhotoCropView(image: selectedImage) { editedImage in
                        self.selectedImage = editedImage
                    }
                }
            case let .videoSlot(index):
                if selectedVideoImages.indices.contains(index),
                   let image = selectedVideoImages[index] {
                    FeaturePhotoCropView(image: image) { editedImage in
                        selectedVideoImages[index] = editedImage
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showLogin, onDismiss: {
            if !isLoggedIn { pendingLoginAction = nil }
        }) {
            SignInView {
                showLogin = false
                let action = pendingLoginAction
                pendingLoginAction = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: action ?? {})
            }
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .cancel(Text("OK"))
            )
        }
        .alert(
            "Generation failed",
            isPresented: Binding(
                get: { generationError != nil },
                set: { if !$0 { generationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { generationError = nil }
        } message: {
            Text(generationError ?? "Please try again.")
        }
    }

    private func noPromptVideoEditor(viewportHeight: CGFloat) -> some View {
        let usesCompactCards = viewportHeight < 650
        let thumbnailWidth: CGFloat = usesCompactCards ? 88 : 96
        let thumbnailHeight: CGFloat = usesCompactCards ? 94 : 108
        let templateChooserHeight = thumbnailHeight + 40
        let reservedHeight = templateChooserHeight + 55 + 61 + 44
        let previewHeight = max(0, min(470, viewportHeight - reservedHeight))

        return VStack(alignment: .leading, spacing: 10) {
            largeSourcePreview(height: previewHeight)

            templateChooser(
                thumbnailWidth: thumbnailWidth,
                thumbnailHeight: thumbnailHeight,
                verticalSpacing: 7
            )
            .frame(height: templateChooserHeight, alignment: .top)

            settingsSummary()

            creationButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func guidedVideoEditor(viewportSize: CGSize) -> some View {
        if viewportSize.width > viewportSize.height, viewportSize.height < 600 {
            landscapeGuidedVideoEditor(viewportSize: viewportSize)
        } else {
            portraitGuidedVideoEditor(viewportSize: viewportSize)
        }
    }

    private func portraitGuidedVideoEditor(viewportSize: CGSize) -> some View {
        let layout = GuidedVideoEditorLayout(viewportSize: viewportSize)

        return VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            videoUploadSlots(
                height: layout.uploadHeight,
                maximumSingleSlotWidth: layout.uploadWidth
            )

            promptCard(height: layout.promptHeight)

            settingsSummary(compact: layout.usesCompactControls)

            creationButton
                .frame(height: layout.buttonHeight)

            templateChooser(
                thumbnailWidth: layout.thumbnailWidth,
                thumbnailHeight: layout.thumbnailHeight,
                verticalSpacing: layout.templateSpacing,
                usesCompactTitle: layout.usesCompactControls
            )
            .frame(height: layout.templateChooserHeight, alignment: .top)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, layout.topPadding)
        .padding(.bottom, layout.bottomPadding)
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .top)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guided-video-editor")
    }

    private func landscapeGuidedVideoEditor(viewportSize: CGSize) -> some View {
        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = 7
        let sectionSpacing: CGFloat = 8
        let contentHeight = max(0, viewportSize.height - verticalPadding * 2)
        let promptHeight = min(120, max(72, contentHeight * 0.38))
        let uploadHeight = max(0, min(180, contentHeight - promptHeight - sectionSpacing))
        let templateTitleHeight: CGFloat = 22
        let templateSpacing: CGFloat = 6
        let chooserHeight = max(
            0,
            contentHeight - 55 - 61 - sectionSpacing * 2
        )
        let thumbnailHeight = max(0, chooserHeight - templateTitleHeight - templateSpacing)

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                videoUploadSlots(
                    height: uploadHeight,
                    maximumSingleSlotWidth: min(150, uploadHeight * 0.76)
                )
                promptCard(height: promptHeight)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: sectionSpacing) {
                settingsSummary(compact: true)
                creationButton
                    .frame(height: 61)
                templateChooser(
                    thumbnailWidth: min(140, thumbnailHeight * 0.74),
                    thumbnailHeight: thumbnailHeight,
                    verticalSpacing: templateSpacing,
                    usesCompactTitle: true
                )
                .frame(height: chooserHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .top)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guided-video-editor")
    }

    private func standardVideoEditor(viewportSize: CGSize) -> some View {
        let compact = viewportSize.height < 650
        let sectionSpacing: CGFloat = compact ? 7 : 10
        let topPadding: CGFloat = 6
        let bottomPadding: CGFloat = 8
        let hasPreview = activeTemplate != nil
        let sectionCount = hasPreview ? 6 : 5
        let chooserTitleHeight: CGFloat = compact ? 22 : 27
        let chooserSpacing: CGFloat = compact ? 6 : 9
        let fixedHeight = topPadding
            + bottomPadding
            + sectionSpacing * CGFloat(sectionCount - 1)
            + 55
            + 61
            + chooserTitleHeight
            + chooserSpacing
        let preferred: [CGFloat] = hasPreview
            ? [220, 160, 120, 150]
            : [190, 140, 190]
        let minimum: [CGFloat] = hasPreview
            ? [90, 80, 70, 80]
            : [90, 75, 90]
        let flexible = UploadPageFlexibleLayout.fittedSizes(
            availableHeight: viewportSize.height - fixedHeight,
            preferred: preferred,
            minimum: minimum
        )
        let flexibleOffset = hasPreview ? 1 : 0
        let previewHeight = hasPreview ? flexible[0] : 0
        let uploadHeight = flexible[flexibleOffset]
        let promptHeight = flexible[flexibleOffset + 1]
        let thumbnailHeight = flexible[flexibleOffset + 2]

        return VStack(alignment: .leading, spacing: sectionSpacing) {
            if let activeTemplate {
                FrostedTemplatePreview(item: activeTemplate)
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppPalette.surfaceEdge.opacity(0.70), lineWidth: 1)
                    )
            }

            videoUploadSlots(
                height: uploadHeight,
                maximumSingleSlotWidth: min(166, uploadHeight * 0.76)
            )
            promptCard(height: promptHeight)
            settingsSummary(compact: compact)
            creationButton
            templateChooser(
                thumbnailHeight: thumbnailHeight,
                verticalSpacing: chooserSpacing,
                usesCompactTitle: compact
            )
            .frame(
                height: chooserTitleHeight + chooserSpacing + thumbnailHeight,
                alignment: .top
            )
        }
        .padding(.horizontal, viewportSize.width < 375 ? 16 : 20)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .top)
        .clipped()
        .accessibilityIdentifier("standard-video-editor")
    }

    private func imageTemplateEditor(viewportSize: CGSize) -> some View {
        let compact = viewportSize.height < 620
        let spacing: CGFloat = compact ? 8 : 12
        let topPadding: CGFloat = 6
        let bottomPadding: CGFloat = 8
        let titleHeight: CGFloat = compact ? 25 : 29
        let fixedHeight = topPadding
            + bottomPadding
            + spacing * 4
            + titleHeight
            + 55
            + 61
        let fitted = UploadPageFlexibleLayout.fittedSizes(
            availableHeight: viewportSize.height - fixedHeight,
            preferred: [316, 190],
            minimum: [130, 90]
        )
        let previewHeight = fitted[0]
        let pickerHeight = fitted[1]
        let pickerWidth = min(142, pickerHeight * 0.75)

        return VStack(alignment: .leading, spacing: spacing) {
            outputPreview(height: previewHeight)

            Text("Upload Image")
                .font(.title2)
                .foregroundStyle(AppPalette.brownInk)
                .frame(height: titleHeight, alignment: .leading)

            sourcePhotoPicker(width: pickerWidth, height: pickerHeight)
                .frame(maxWidth: .infinity)

            settingsSummary(compact: compact)

            creationButton
        }
        .padding(.horizontal, viewportSize.width < 375 ? 16 : 20)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .top)
        .clipped()
        .accessibilityIdentifier("image-template-editor")
    }

    private func largeSourcePreview(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            FrostedUploadPreview(image: selectedImage, template: activeTemplate)
                .frame(maxWidth: .infinity)
                .frame(height: height)

            LinearGradient(
                colors: [.clear, .black.opacity(0.48)],
                startPoint: .center,
                endPoint: .bottom
            )

            Button {
                photoSelectionTarget = .source
            } label: {
                Label(selectedImage == nil ? "Choose Photo" : "Change Photo", systemImage: "photo.badge.plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 52)
                    .background(.black.opacity(0.38), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.84), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
        }
        // The gradient is a flexible view and can otherwise make this ZStack
        // taller than its media, leaving page background above the preview.
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppPalette.surfaceEdge.opacity(0.70), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if selectedImage != nil {
                PhotoEditButton {
                    cropTarget = .source
                }
                .padding(14)
            }
        }
    }

    private func sourcePhotoPicker(width: CGFloat, height: CGFloat) -> some View {
        Button {
            photoSelectionTarget = .source
        } label: {
            ZStack(alignment: .bottom) {
                sourceMedia
                    .frame(width: width, height: height)

                LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .center, endPoint: .bottom)

                HStack {
                    Text(selectedImage == nil ? "Image1" : "Selected")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "crop")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(10)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 31, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppPalette.surfaceEdge.opacity(0.78), lineWidth: 1)
            )
        }
        .buttonStyle(TemplatePressStyle())
        .accessibilityLabel(selectedImage == nil ? "Choose source photo" : "Change source photo")
        .overlay(alignment: .bottomTrailing) {
            if selectedImage != nil {
                PhotoEditButton {
                    cropTarget = .source
                }
                .padding(8)
            }
        }
    }

    private func outputPreview(height: CGFloat) -> some View {
        ZStack {
            if let activeTemplate {
                FrostedTemplatePreview(item: activeTemplate)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            } else {
                ContentUnavailableView("Choose a template", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppPalette.surfaceEdge.opacity(0.70), lineWidth: 1)
        )
    }

    private var sourceMedia: some View {
        Group {
            if let selectedImage {
                FrostedUploadedPhoto(image: selectedImage)
            } else if let activeTemplate {
                TemplateMediaView(item: activeTemplate, gravity: .resizeAspectFill)
            } else {
                ZStack {
                    Color.white.opacity(0.55)
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(AppPalette.surfaceEdge)
                }
            }
        }
        .clipped()
    }

    private func promptCard(height: CGFloat = 150) -> some View {
        FeaturePromptBox(
            text: $prompt,
            placeholder: "Describe how Image1, Image2 and Image3 should be combined.",
            height: height,
            isEditable: flow.promptIsEditable
        )
        .accessibilityLabel("Generation prompt")
    }

    private func templateChooser(
        thumbnailWidth: CGFloat? = nil,
        thumbnailHeight: CGFloat? = nil,
        verticalSpacing: CGFloat = 12,
        usesCompactTitle: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            Text("Choose Template")
                .font(usesCompactTitle ? .headline.bold() : .title2.bold())
                .foregroundStyle(AppPalette.ink)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(flow.templates) { item in
                        let resolvedWidth = thumbnailWidth ?? 158
                        let resolvedHeight = thumbnailHeight ?? 214

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectTemplate(item)
                            }
                        } label: {
                            ZStack(alignment: .bottom) {
                                TemplateMediaView(
                                    item: item,
                                    gravity: .resizeAspectFill,
                                    playsVideo: true
                                )
                                    .frame(
                                        width: resolvedWidth,
                                        height: resolvedHeight,
                                        alignment: flow.family == .videoNoPrompt ? .top : .center
                                    )
                                    .clipped()

                                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)

                                TemplateThumbnailTitle(title: item.title)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .padding(.horizontal, 7)
                                    .padding(.bottom, 8)
                            }
                            .frame(width: resolvedWidth, height: resolvedHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        activeTemplate?.id == item.id ? AppPalette.accent : Color.clear,
                                        lineWidth: 3
                                    )
                            )
                        }
                        .buttonStyle(TemplatePressStyle())
                        .accessibilityLabel("Select \(item.title)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("creation-template-strip")
        }
    }

    private func settingsSummary(compact: Bool = false) -> some View {
        Button {
            showOptions = true
        } label: {
            HStack(spacing: compact ? 6 : 9) {
                if flow.isImageFlow {
                    parameterPill("\(outputCount) Img", compact: compact)
                    parameterPill(imageResolution, compact: compact)
                    if let imageRatio = imageCapabilities.normalizedAspectRatio(ratio) {
                        parameterPill(imageRatio, compact: compact)
                    }
                } else {
                    if videoCapabilities.supportsSound {
                        Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
                            .background(AppPalette.backgroundTop, in: Circle())
                    }
                    if videoCapabilities.supportsMultiShot {
                        Image(systemName: multiShotEnabled ? "video.badge.waveform.fill" : "video.slash.fill")
                            .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
                            .background(AppPalette.backgroundTop, in: Circle())
                    }
                    parameterPill(duration, compact: compact)
                    parameterPill(videoResolution, compact: compact)
                    if flow.family != .videoNoPrompt {
                        parameterPill(ratio, compact: compact)
                    }
                }

                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .foregroundStyle(AppPalette.surfaceEdge)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(height: 55)
            .background(Color(.systemBackground).opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppPalette.surfaceEdge.opacity(0.72), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit generation settings")
    }

    private func parameterPill(_ text: String, compact: Bool = false) -> some View {
        Text(text)
            .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
            .padding(.horizontal, compact ? 8 : 13)
            .frame(height: compact ? 30 : 34)
            .background(AppPalette.backgroundTop, in: Capsule())
    }

    private var creationButton: some View {
        Button {
            requireLogin {
                guard credits >= currentCost else {
                    AppAnalytics.generationBlocked(
                        contentType: flow.isImageFlow ? "image" : "video",
                        itemID: (activeTemplate ?? template)?.id,
                        reason: "insufficient_credits"
                    )
                    showCredits = true
                    return
                }

                if flow.isImageFlow {
                    credits -= currentCost
                    isCreating = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(850))
                        isCreating = false
                        notice = .queued
                    }
                } else {
                    startVideoGeneration()
                }
            }
        } label: {
            ZStack {
                if isCreating {
                    ProgressView()
                        .tint(.white)
                } else {
                    VStack(spacing: 0) {
                        Text(credits >= currentCost ? "Create" : "More Credits")
                            .font(.title3.bold())
                        if credits < currentCost {
                            Text("Not enough credits")
                                .font(.caption)
                        }
                    }
                }

                HStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Image("RewardsCreditToken")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        Text("\(currentCost)")
                            .font(.headline)
                            .foregroundStyle(Color.yellow)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 61)
            .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppPalette.ink, lineWidth: 1))
        }
        .buttonStyle(TemplatePressStyle())
        .disabled(isCreating)
        .accessibilityIdentifier("creation-primary-action")
    }

    private var currentCost: Int {
        if flow.isImageFlow {
            return creditPricing.otherImageCredits
        }

        let normalizedDuration = videoCapabilities.normalizedDuration(duration)
        let normalizedResolution = videoCapabilities.normalizedResolution(videoResolution)
        let seconds = Int(normalizedDuration.trimmingCharacters(in: CharacterSet.decimalDigits.inverted))
            ?? creditPricing.videoDefaultDurationSeconds
        return creditPricing.videoGenerationCredits(
            duration: seconds,
            resolution: normalizedResolution,
            sound: videoCapabilities.supportsSound && soundEnabled,
            multiShot: videoCapabilities.supportsMultiShot && multiShotEnabled
        )
    }

    private var videoCapabilities: VideoGenerationOptionCapabilities {
        .current(forModelID: (activeTemplate ?? template)?.modelID)
    }

    private var imageCapabilities: ImageGenerationOptionCapabilities {
        .current(forModelID: (activeTemplate ?? template)?.modelID)
    }

    private func requireLogin(_ action: @escaping () -> Void) {
        guard isLoggedIn || ProcessInfo.processInfo.arguments.contains("-loggedIn") else {
            pendingLoginAction = action
            AppAnalytics.authGateShown(source: "generation")
            showLogin = true
            return
        }
        action()
    }

    private func startVideoGeneration() {
        guard pendingVideoGeneration == nil else { return }

        let images: [UIImage]
        if flow.family == .videoNoPrompt {
            images = selectedImage.map { [$0] } ?? []
        } else {
            images = selectedVideoImages.compactMap { $0 }
        }
        guard !images.isEmpty else {
            AppAnalytics.generationBlocked(
                contentType: "video",
                itemID: (activeTemplate ?? template)?.id,
                reason: "missing_media"
            )
            generationError = "Please choose at least one source photo."
            return
        }

        let normalizedDuration = videoCapabilities.normalizedDuration(duration)
        let normalizedResolution = videoCapabilities.normalizedResolution(videoResolution)
        let normalizedRatio = videoCapabilities.normalizedAspectRatio(ratio)
        let normalizedSound = videoCapabilities.supportsSound && soundEnabled
        let normalizedMultiShot = videoCapabilities.supportsMultiShot && multiShotEnabled

        guard let seconds = Int(normalizedDuration.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)) else {
            AppAnalytics.generationBlocked(
                contentType: "video",
                itemID: (activeTemplate ?? template)?.id,
                reason: "invalid_duration"
            )
            generationError = "The selected video duration is invalid."
            return
        }

        let selectedTemplate = activeTemplate ?? template
        guard let selectedTemplate else {
            AppAnalytics.generationBlocked(
                contentType: "video",
                itemID: nil,
                reason: "missing_template"
            )
            generationError = "Please choose a video template."
            return
        }

        // The prompt box contains a polished, display-only summary. Unless the
        // user explicitly edits it, let the server keep using the canonical CMS
        // prompt so the established template result does not change.
        let editablePrompt = VideoPromptSubmission.userOverride(
            displayedPrompt: prompt,
            defaultDisplayedPrompt: CreationFlowConfiguration(
                template: selectedTemplate,
                templateOptions: templates
            ).prompt,
            isEditable: flow.promptIsEditable
        )

        let options = PhotoReviveVideoGenerationOptions(
            resolution: normalizedResolution,
            aspectRatio: normalizedRatio,
            duration: seconds,
            sound: normalizedSound,
            multiShot: normalizedMultiShot
        )

        AppAnalytics.generationStarted(
            contentType: "video",
            itemID: selectedTemplate.id,
            creditsCost: currentCost,
            inputCount: images.count,
            resolution: normalizedResolution,
            durationSeconds: seconds,
            soundEnabled: normalizedSound,
            multiShotEnabled: normalizedMultiShot
        )

        generationError = nil
        pendingVideoGeneration = PendingVideoGenerationRequest(
            endpoint: .imageToVideo,
            itemID: selectedTemplate.id,
            images: images,
            prompt: editablePrompt,
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            options: options
        )
        showGenerationFlow = true
    }

    private func closeGenerationFlow() {
        showGenerationFlow = false
        isCreating = false
        pendingVideoGeneration = nil
    }

    private func applySelectedPhotos(
        _ images: [UIImage],
        to target: CreateFlowPhotoSelectionTarget
    ) {
        guard !images.isEmpty else { return }
        switch target {
        case .source:
            selectedImage = images[0]
        case .videoSlots:
            var updatedImages = selectedVideoImages
            if images.count == 1,
               let emptyIndex = updatedImages.firstIndex(where: { $0 == nil }) {
                updatedImages[emptyIndex] = images[0]
            } else {
                for (index, image) in images.prefix(updatedImages.count).enumerated() {
                    updatedImages[index] = image
                }
            }
            selectedVideoImages = updatedImages
        }
    }

    private func selectTemplate(_ item: TemplateItem) {
        activeTemplate = item
        applyVideoCapabilities(.current(forModelID: item.modelID))
        applyImageCapabilities(.current(forModelID: item.modelID))
        prompt = CreationFlowConfiguration(template: item, templateOptions: templates).prompt
        let count = max(1, item.imageUploadCount)
        if selectedVideoImages.count != count {
            selectedVideoImages = Array((selectedVideoImages + Array(repeating: nil, count: count)).prefix(count))
        }
    }

    private func applyVideoCapabilities(_ capabilities: VideoGenerationOptionCapabilities) {
        duration = capabilities.normalizedDuration(duration)
        videoResolution = capabilities.normalizedResolution(videoResolution)
        ratio = capabilities.normalizedAspectRatio(ratio)
        if !capabilities.supportsSound { soundEnabled = false }
        if !capabilities.supportsMultiShot { multiShotEnabled = false }
    }

    private func applyImageCapabilities(_ capabilities: ImageGenerationOptionCapabilities) {
        imageResolution = capabilities.normalizedResolution(imageResolution)
        outputCount = capabilities.normalizedOutputCount(outputCount)
        if let normalizedRatio = capabilities.normalizedAspectRatio(ratio) {
            ratio = normalizedRatio
        }
    }

    private func videoUploadSlots(
        height: CGFloat = 214,
        maximumSingleSlotWidth: CGFloat = 166
    ) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 14
            let uploadCount = flow.imageUploadCount
            let preferredItemWidth = min(
                maximumSingleSlotWidth,
                max(118, height * 0.74)
            )
            let stripLayout = HorizontalUploadStripLayout(
                viewportWidth: proxy.size.width,
                itemCount: uploadCount,
                preferredItemWidth: preferredItemWidth,
                spacing: spacing
            )

            if stripLayout.scrollsHorizontally {
                ScrollView(.horizontal) {
                    videoUploadSlotRow(
                        uploadCount: uploadCount,
                        itemWidth: stripLayout.itemWidth,
                        contentWidth: stripLayout.contentWidth,
                        spacing: spacing,
                        height: height
                    )
                    .frame(minWidth: proxy.size.width, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("video-upload-strip")
            } else {
                videoUploadSlotRow(
                    uploadCount: uploadCount,
                    itemWidth: stripLayout.itemWidth,
                    contentWidth: stripLayout.contentWidth,
                    spacing: spacing,
                    height: height
                )
                .frame(width: proxy.size.width, alignment: .leading)
            }
        }
        .frame(height: height)
    }

    private func videoUploadSlotRow(
        uploadCount: Int,
        itemWidth: CGFloat,
        contentWidth: CGFloat,
        spacing: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            Button {
                photoSelectionTarget = .videoSlots
            } label: {
                HStack(spacing: spacing) {
                    ForEach(0..<uploadCount, id: \.self) { index in
                        ImageGenerationUploadSlot(
                            image: selectedVideoImages.indices.contains(index) ? selectedVideoImages[index] : nil,
                            label: "Image\(index + 1)",
                            placeholderURL: activeTemplate?.uploadPlaceholderURL(at: index),
                            height: height
                        )
                        .frame(width: itemWidth, height: height)
                        .accessibilityIdentifier("video-image-upload-slot-\(index + 1)")
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: spacing) {
                ForEach(0..<uploadCount, id: \.self) { index in
                    UploadPhotoEditOverlay(
                        hasImage: selectedVideoImages.indices.contains(index)
                            && selectedVideoImages[index] != nil,
                        width: itemWidth,
                        height: height,
                        action: { cropTarget = .videoSlot(index) }
                    )
                }
            }
        }
        .frame(width: contentWidth, height: height, alignment: .leading)
    }

    private var flow: CreationFlowConfiguration {
        CreationFlowConfiguration(template: activeTemplate ?? template, templateOptions: templates)
    }
}

/// Keeps every template sample fully visible on upload screens. Any unused
/// space is filled with a softly blurred copy of the same image or video.
private struct FrostedTemplatePreview: View {
    let item: TemplateItem

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                FrostedTemplateBackdrop(item: item)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: 22)
                    .scaleEffect(1.18)

                Color.black.opacity(0.05)

                TemplateMediaView(
                    item: item,
                    gravity: .resizeAspect,
                    imageContentMode: .fit,
                    aspectFitVideoBackgroundColor: .clear,
                    showsLoadingPlaceholder: false
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                // A small overscan removes the hairline that aspect-fit media
                // can leave at the top and bottom of portrait preview frames.
                // The frosted side fill is intentionally allowed to narrow.
                .scaleEffect(1.06)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .background(Color(.systemGray4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title) sample preview")
        .accessibilityIdentifier("upload-sample-preview")
    }
}

/// Fits a thumbnail title by its longest word before SwiftUI lays out two
/// lines. This keeps words such as "Amusement" from splitting mid-word on
/// compact cards while preserving the normal wrap at spaces.
private struct TemplateThumbnailTitle: View {
    let title: String

    var body: some View {
        GeometryReader { proxy in
            Text(title)
                .font(.system(size: fittedFontSize(for: proxy.size.width), weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .allowsTightening(true)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .bottom
                )
        }
    }

    private func fittedFontSize(for availableWidth: CGFloat) -> CGFloat {
        let maximumSize: CGFloat = 15
        let minimumSize: CGFloat = 9
        let words = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let font = UIFont.systemFont(ofSize: maximumSize, weight: .medium)
        let wordWidth = words
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0

        guard wordWidth > 0, availableWidth > 0 else { return maximumSize }
        return max(minimumSize, floor(maximumSize * min(1, availableWidth / wordWidth)))
    }
}

/// A dedicated aspect-fill layer for the frosted surround. It intentionally
/// bypasses the foreground's aspect-preservation rules used by comparison
/// videos, otherwise those special templates would expose the page color.
private struct FrostedTemplateBackdrop: View {
    let item: TemplateItem

    var body: some View {
        Group {
            if let comparisonCover = item.comparisonCover {
                TemplateComparisonView(cover: comparisonCover, imageContentMode: .fill)
            } else if !item.imageName.isEmpty {
                Image(item.imageName)
                    .resizable()
                    .scaledToFill()
            } else if let coverImageURL = item.coverImageURL {
                CachedRemoteImage(url: coverImageURL) { image in
                    Image(uiImage: image).resizable().scaledToFill()
                } placeholder: {
                    TemplateMediaView(item: item, gravity: .resizeAspectFill)
                } failure: {
                    TemplateMediaView(item: item, gravity: .resizeAspectFill)
                }
            } else {
                TemplateMediaView(item: item, gravity: .resizeAspectFill)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct FrostedUploadPreview: View {
    let image: UIImage?
    let template: TemplateItem?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    FrostedUploadedPhoto(image: image)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else if let template {
                    FrostedTemplatePreview(item: template)
                } else {
                    ZStack {
                        Color.white.opacity(0.55)
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(AppPalette.surfaceEdge)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .background(Color(.systemGray4))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("upload-sample-preview")
    }
}

private enum CreationNotice: String, Identifiable {
    case help
    case queued

    var id: String { rawValue }

    var title: String {
        switch self {
        case .help: "How it works"
        case .queued: "Creation queued"
        }
    }

    var message: String {
        switch self {
        case .help:
            "Choose a clear source photo, select a template and review the output settings before creating."
        case .queued:
            "Your creation has been added to My Creations."
        }
    }
}

private struct GenerationOptionsSheet: View {
    let isImageFlow: Bool
    let videoCapabilities: VideoGenerationOptionCapabilities
    let imageCapabilities: ImageGenerationOptionCapabilities
    @Binding var soundEnabled: Bool
    @Binding var multiShotEnabled: Bool
    @Binding var duration: String
    @Binding var videoResolution: String
    @Binding var imageResolution: String
    @Binding var ratio: String
    @Binding var outputCount: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isImageFlow {
                        optionSection(
                            "Resolution",
                            values: imageCapabilities.resolutions,
                            selection: $imageResolution,
                            columns: 3
                        )
                        if !imageCapabilities.aspectRatios.isEmpty {
                            optionSection(
                                "Ratio",
                                values: imageCapabilities.aspectRatios,
                                selection: $ratio,
                                columns: 3
                            )
                        }
                        // The current image endpoints return one canonical
                        // output URL. Do not advertise unsupported batch output.
                        optionSection(
                            "Output Image Number",
                            values: imageCapabilities.outputCounts,
                            selection: $outputCount,
                            columns: 1
                        )
                    } else {
                        if videoCapabilities.supportsSound {
                            binarySection(
                                "Sounds",
                                offIcon: "speaker.slash.fill",
                                onIcon: "speaker.wave.2.fill",
                                isOn: $soundEnabled
                            )
                        }
                        if videoCapabilities.supportsMultiShot {
                            binarySection(
                                "Multi-Shot Video",
                                offIcon: "video.slash.fill",
                                onIcon: "video.badge.waveform.fill",
                                isOn: $multiShotEnabled
                            )
                        }
                        optionSection("Duration", values: videoCapabilities.durations, selection: $duration, columns: 3)
                        optionSection(
                            "Resolution",
                            values: videoCapabilities.resolutions,
                            selection: $videoResolution,
                            columns: 3
                        )
                        optionSection(
                            "Ratio",
                            values: videoCapabilities.aspectRatios,
                            selection: $ratio,
                            columns: 3
                        )
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Output Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Save output settings")
                }
            }
        }
        .tint(AppPalette.accent)
        .onAppear(perform: normalizeSelections)
    }

    private func normalizeSelections() {
        guard !isImageFlow else {
            imageResolution = imageCapabilities.normalizedResolution(imageResolution)
            outputCount = imageCapabilities.normalizedOutputCount(outputCount)
            if let normalizedRatio = imageCapabilities.normalizedAspectRatio(ratio) {
                ratio = normalizedRatio
            }
            return
        }
        duration = videoCapabilities.normalizedDuration(duration)
        videoResolution = videoCapabilities.normalizedResolution(videoResolution)
        ratio = videoCapabilities.normalizedAspectRatio(ratio)
        if !videoCapabilities.supportsSound { soundEnabled = false }
        if !videoCapabilities.supportsMultiShot { multiShotEnabled = false }
    }

    private func binarySection(
        _ title: String,
        offIcon: String,
        onIcon: String,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3)

            HStack(spacing: 14) {
                binaryButton(icon: offIcon, selected: !isOn.wrappedValue) {
                    isOn.wrappedValue = false
                }
                binaryButton(icon: onIcon, selected: isOn.wrappedValue) {
                    isOn.wrappedValue = true
                }
            }
        }
    }

    private func binaryButton(icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(selected ? AppPalette.accent : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? AppPalette.accent : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func optionSection(
        _ title: String,
        values: [String],
        selection: Binding<String>,
        columns: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns), spacing: 12) {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection.wrappedValue = value
                    } label: {
                        Text(value)
                            .font(.body.weight(.medium))
                            .foregroundStyle(selection.wrappedValue == value ? AppPalette.accent : Color.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        selection.wrappedValue == value ? AppPalette.accent : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CreationFlowConfiguration {
    enum Family: Equatable {
        case videoNoPrompt
        case videoPrompt
        case image
        case standard
    }

    let template: TemplateItem?
    let templateOptions: [TemplateItem]?

    var family: Family {
        guard let template else { return .standard }
        // CMS menu=image is always the image upload page. Its one-image or
        // two-image variant is controlled separately by material requirements.
        if template.generationKind == .image { return .image }
        // CMS menu=video has exactly two upload-page variants. The prompt
        // switch is stored on the template itself, never inferred from media.
        return template.showsPrompt ? .videoPrompt : .videoNoPrompt
    }

    var title: String {
        switch family {
        case .videoNoPrompt, .videoPrompt:
            template?.detailGroupTitle ?? template?.title ?? "Create with AI"
        case .image: "Raging Battle"
        case .standard: template?.title ?? "Create with AI"
        }
    }

    var templates: [TemplateItem] {
        if let templateOptions, !templateOptions.isEmpty {
            return templateOptions
        }

        switch family {
        case .videoNoPrompt:
            return [TemplateCatalog.memory, TemplateCatalog.gentleman, TemplateCatalog.fashion, TemplateCatalog.cowboy]
        case .videoPrompt:
            return [TemplateCatalog.babyFly, TemplateCatalog.motorcycle, TemplateCatalog.skiing, TemplateCatalog.cartoon]
        case .image:
            return [TemplateCatalog.mangaRide, TemplateCatalog.cartoon, TemplateCatalog.anime]
        case .standard:
            return [TemplateCatalog.cartoon, TemplateCatalog.anime, TemplateCatalog.mangaRide, TemplateCatalog.memory]
        }
    }

    var prompt: String {
        switch family {
        case .videoNoPrompt:
            ""
        case .videoPrompt:
            if let displayedPrompt = template?.displayedPromptTemplate {
                displayedPrompt
            } else if template?.promptTemplate != nil {
                template?.promptIsEditable == true ? "" : "Prompt configured by the template."
            } else {
                "Use the uploaded image as the visual reference and preserve the subject's identity throughout the video."
            }
        case .image:
            "Use the uploaded image as the visual reference and apply the selected illustrated style while preserving the subject and composition."
        case .standard:
            "Use the uploaded image as the source. Keep the subject recognizable and apply the selected template with natural detail and motion."
        }
    }

    var isImageFlow: Bool { family == .image }
    var showsHelp: Bool { family == .videoNoPrompt }
    var imageUploadCount: Int { template?.imageUploadCount ?? 1 }
    var promptIsEditable: Bool { template?.promptIsEditable ?? false }
}

private enum VideoGenerationStage: Equatable {
    case loading
    case result
    case saved
    case failed(String)
}

private struct VideoGenerationFlowView: View {
    let title: String
    let templateTitle: String
    let videoName: String?
    let template: TemplateItem?
    var taskID: String? = nil
    var loadingPreviewImage: UIImage? = nil
    var submissionAction: (@MainActor () async throws -> PhotoReviveVideoGenerationSubmission)? = nil
    var onSubmission: ((PhotoReviveVideoGenerationSubmission) -> Void)? = nil
    let onRegenerate: () -> Void
    let onClose: () -> Void

    @State private var stage: VideoGenerationStage = .loading
    @State private var generatedVideoURL: URL?
    @State private var selectedTab: AppTab = .me
    @State private var showPreview = false
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var settingsCredits = 0
    @State private var showDeleteConfirmation = false
    @State private var isExporting = false
    @State private var isDeleting = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var exportError: String?
    @State private var pollingStartedAt = Date()
    @State private var submittedTaskID: String?
    @State private var hasStartedBackgroundWork = false
    @State private var progressRecordID: UUID?
    @AppStorage("isSubscribed") private var isSubscribed = false

    var body: some View {
        ZStack {
            PaperTextureBackground()

            Group {
                switch stage {
                case .loading:
                    loadingContent
                case .result:
                    resultContent
                case .saved:
                    savedContent
                case .failed(let message):
                    failedContent(message: message)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if stage != .saved {
                BottomTabBar(selection: $selectedTab, onSelect: navigateToMainTab)
            }
        }
        .onAppear {
            startBackgroundWorkIfNeeded()
        }
        .fullScreenCover(isPresented: $showPreview) {
            VideoGenerationPreviewView(
                videoName: videoName,
                template: template,
                generatedVideoURL: generatedVideoURL,
                onClose: { showPreview = false },
                onRegenerate: {
                    showPreview = false
                    onRegenerate()
                },
                onSave: {
                    showPreview = false
                    saveVideo()
                },
                onShare: {
                    showPreview = false
                    shareVideo()
                },
                onRemoveWatermark: {
                    showPreview = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showPaywall = true
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallOfferFlowView(analyticsSource: "video_remove_watermark")
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(credits: $settingsCredits)
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                GeneratedMediaActivityView(activityItems: [shareURL])
            }
        }
        .alert(
            "Permanently delete this creation?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive, action: deleteGeneration)
        } message: {
            Text("This creation will be permanently deleted and cannot be recovered.")
        }
        .alert(
            "Export unavailable",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Please try again.")
        }
        .preferredColorScheme(.light)
        .onAppear {
            AppAnalytics.screen(
                "video_generation_progress",
                className: "VideoGenerationFlowView"
            )
        }
    }

    @MainActor
    private func startBackgroundWorkIfNeeded() {
        guard stage == .loading, !hasStartedBackgroundWork else { return }
        hasStartedBackgroundWork = true
        let shouldTrackProgress: Bool
#if DEBUG
        shouldTrackProgress = submissionAction != nil
            || taskID != nil
            || ProcessInfo.processInfo.arguments.contains("-holdGeneratedVideoLoading")
#else
        shouldTrackProgress = submissionAction != nil || taskID != nil
#endif
        if shouldTrackProgress {
            progressRecordID = BackgroundGenerationWorkStore.shared.register(
                kind: .video,
                title: title,
                subtitle: templateTitle,
                previewImage: loadingPreviewImage,
                serverTaskID: taskID
            )
        }
        let recordID = progressRecordID
        BackgroundGenerationWorkStore.shared.start {
            await runLoadingFlow(progressRecordID: recordID)
        }
    }

    private func navigateToMainTab(_ tab: AppTab) {
        selectedTab = tab
        onClose()
        let historyKind = tab == .me ? MeHistoryKind.video.rawValue : nil
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .appTabNavigationRequested,
                object: tab,
                userInfo: historyKind.map {
                    [Notification.Name.appTabNavigationHistoryKindKey: $0]
                }
            )
        }
    }

    @MainActor
    private func runLoadingFlow(progressRecordID: UUID?) async {
        if let submissionAction {
            do {
                // Let the full-screen cover finish presenting before JPEG
                // encoding starts. Encoding large source photos can otherwise
                // block the first rendered frame and leave the editor visible.
                try await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, stage == .loading else { return }
                let submission = try await submissionAction()
                guard !Task.isCancelled, stage == .loading else { return }
                submittedTaskID = submission.taskID
                BackgroundGenerationWorkStore.shared.markSubmitted(
                    recordID: progressRecordID,
                    serverTaskID: submission.taskID
                )
                onSubmission?(submission)
                await AppAccountStore.shared.refreshHistory()
                BackgroundGenerationWorkStore.shared.reconcile(
                    with: AppAccountStore.shared.historyTasks
                )
                AppAnalytics.generationSubmitted(
                    contentType: "video",
                    itemID: template?.id
                )
                pollingStartedAt = Date()
                await pollGenerationTask(
                    submission.taskID,
                    progressRecordID: progressRecordID
                )
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.userFacingEnglishMessage(
                    fallback: "Video generation failed. Please try again."
                )
                BackgroundGenerationWorkStore.shared.markFailed(
                    recordID: progressRecordID,
                    message: message
                )
                AppAnalytics.generationFailed(
                    contentType: "video",
                    itemID: template?.id,
                    stage: "submission",
                    failureType: AppAnalytics.apiFailureType(error)
                )
                stage = .failed(message)
            }
        } else if let taskID {
            submittedTaskID = taskID
            pollingStartedAt = Date()
            await pollGenerationTask(taskID, progressRecordID: progressRecordID)
        } else {
            // Legacy preview-only callers keep their existing handoff.
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-showGeneratedVideoPreview") {
                generatedVideoURL = Bundle.main.url(
                    forResource: "OnboardingRestoreVideo",
                    withExtension: "mp4"
                )
            }
#endif
#if DEBUG
            let previewDelay = ProcessInfo.processInfo.arguments.contains("-holdGeneratedVideoLoading")
                ? 30_000
                : 2_400
#else
            let previewDelay = 2_400
#endif
            try? await Task.sleep(for: .milliseconds(previewDelay))
            guard !Task.isCancelled, stage == .loading else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                stage = .result
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 14) {
            HStack(spacing: 0) {
                Button {
                    navigateToMainTab(.video)
                } label: {
                    Text("Video")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppPalette.accent)
                        .frame(width: 82, height: 43)
                        .background(Color.white.opacity(0.42), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Browse AI Video")

                Button {
                    navigateToMainTab(.photo)
                } label: {
                    Text("Photo")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                        .frame(width: 82, height: 43)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Browse AI Photo")
            }
            .padding(3)
            .background(Color.white.opacity(0.24), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.68), lineWidth: 1))

            Spacer(minLength: 0)

            Button {
                settingsCredits = AppAccountStore.shared.creditsBalance
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.48), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Generation settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var loadingContent: some View {
        VStack(spacing: 0) {
            workspaceHeader

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 25, weight: .heavy))
                    .foregroundStyle(AppPalette.ink)

                Text(templateTitle)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppPalette.brownInk)

                ZStack {
                    generationMedia(gravity: .resizeAspectFill)
                        .blur(radius: 13)
                        .scaleEffect(1.12)

                    Color.black.opacity(0.40)

                    VStack(spacing: 28) {
                        VideoGenerationDots()
                        Text("Please wait (1-3 min)")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.32))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 204)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.top, 8)

                Button(action: onRegenerate) {
                    Label("Continue Creating", systemImage: "plus.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppPalette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Continue Creating")
                .accessibilityIdentifier("video-generation-continue-creating")
                .accessibilityHint("Returns to the editor while this video continues generating")
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)

            Text("You are responsible for your rendered content. Use our app\nlegally and ethically. Our policies apply.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppPalette.brownInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.top, 38)

            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("video-generation-loading")
    }

    private var resultContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    workspaceHeader

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title)
                                .font(.system(size: 25, weight: .heavy))
                                .foregroundStyle(AppPalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text(templateTitle)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(AppPalette.brownInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .layoutPriority(1)
                        Spacer(minLength: 12)
                        Text("Today")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AppPalette.brownInk)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 53)

                    generatedVideoCard
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    HStack(spacing: 0) {
                        Button {
                            saveVideo()
                        } label: {
                            Label("Save", systemImage: "arrow.down.to.line")
                                .font(.system(size: 21, weight: .medium))
                                .foregroundStyle(AppPalette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                        .disabled(isExporting)
                        .accessibilityLabel("Save generated video")

                        if !isSubscribed {
                            Divider()

                            Button {
                                showPaywall = true
                            } label: {
                                Label("No Watermark", systemImage: "eraser")
                                    .font(.system(size: 21, weight: .medium))
                                    .foregroundStyle(AppPalette.ink)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove watermark")
                        }
                    }
                    .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.72), lineWidth: 1))
                    .padding(.horizontal, 20)

                    sharePanel
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    legalNotice
                        .padding(.top, 35)
                        .padding(.bottom, 103)
                }
                // A vertical ScrollView otherwise adopts the six share buttons'
                // ideal width and recenters the whole screen beyond both edges.
                .frame(width: proxy.size.width, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("video-generation-result")
    }

    private func failedContent(message: String) -> some View {
        VStack(spacing: 22) {
            workspaceHeader
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppPalette.accent)
            Text("Video generation failed")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(AppPalette.ink)
            Text(message)
                .font(.body)
                .foregroundStyle(AppPalette.brownInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again", action: onRegenerate)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .frame(height: 50)
                .background(AppPalette.accent, in: Capsule())
            Spacer()
        }
    }

    private var generatedVideoCard: some View {
        ZStack {
            Color.black

            generationMedia(gravity: .resizeAspect, autoplaysGeneratedVideo: false)

            GeneratedContentWatermark()
                .allowsHitTesting(false)

            Button {
                showPreview = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.54), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.76), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(12)
            .accessibilityLabel("Maximize generated video")

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: isDeleting ? "hourglass" : "trash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.54), in: Circle())
                    .overlay(Circle().stroke(AppPalette.accent.opacity(0.9), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(12)
            .accessibilityLabel("Delete generation")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 204)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var sharePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Share to:")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(AppPalette.ink)

            ViewThatFits(in: .horizontal) {
                shareButtonRow(iconSize: 45, spacing: 4)
                shareButtonRow(iconSize: 36, spacing: 0)
            }
        }
        .padding(17)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.72), lineWidth: 1))
    }

    private var savedContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    stage = .result
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(AppPalette.ink)
                        .frame(width: 58, height: 58)
                        .background(Color.white.opacity(0.58), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to generated video")

                Spacer()

                Text("Share")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(AppPalette.ink)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "house")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(AppPalette.ink)
                        .frame(width: 58, height: 58)
                        .background(Color.white.opacity(0.58), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Return home")
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            Label("Saved successfully", systemImage: "checkmark.circle")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(AppPalette.accent)
                .padding(.top, 62)

            ZStack {
                generationMedia(gravity: .resizeAspectFill)
                GeneratedContentWatermark()
            }
            .frame(width: 244, height: 432)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppPalette.surfaceEdge.opacity(0.74), lineWidth: 1))
            .padding(.top, 55)

            if !isSubscribed {
                Button {
                    showPaywall = true
                } label: {
                    Label("Remove Watermark", systemImage: "eraser")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.43))
                        .padding(.horizontal, 27)
                        .frame(height: 53)
                        .background(AppPalette.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove watermark")
                .padding(.top, 11)
            }

            Spacer(minLength: 26)

            ViewThatFits(in: .horizontal) {
                shareButtonRow(iconSize: 45, spacing: 4)
                shareButtonRow(iconSize: 36, spacing: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private func shareButtonRow(iconSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            VideoShareIcon(symbol: "message.fill", color: Color(red: 0.08, green: 0.78, blue: 0.27), label: "WhatsApp", size: iconSize, action: shareVideo)
                .frame(maxWidth: .infinity)
            VideoShareIcon(symbol: "bubble.left.and.bubble.right.fill", color: Color(red: 0.11, green: 0.81, blue: 0.25), label: "Messages", size: iconSize, action: shareVideo)
                .frame(maxWidth: .infinity)
            VideoShareIcon(symbol: "bolt.horizontal.circle.fill", color: Color(red: 0.43, green: 0.36, blue: 0.97), label: "Messenger", size: iconSize, action: shareVideo)
                .frame(maxWidth: .infinity)
            VideoShareIcon(symbol: "f.cursive", color: Color(red: 0.06, green: 0.37, blue: 0.95), label: "Facebook", size: iconSize, action: shareVideo)
                .frame(maxWidth: .infinity)
            VideoShareIcon(symbol: "camera.fill", color: Color(red: 0.90, green: 0.15, blue: 0.54), label: "Instagram", size: iconSize, action: shareVideo)
                .frame(maxWidth: .infinity)
            VideoShareIcon(symbol: "music.note", color: .black, label: "TikTok", size: iconSize, action: shareVideo)
                .frame(maxWidth: .infinity)
        }
    }

    private var legalNotice: some View {
        Text("You are responsible for your rendered content. Use our app\nlegally and ethically. Our policies apply.")
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(AppPalette.brownInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
    }

    @ViewBuilder
    private func generationMedia(
        gravity: AVLayerVideoGravity,
        autoplaysGeneratedVideo: Bool = true
    ) -> some View {
        if let generatedVideoURL {
            GeneratedVideoPlayerView(
                url: generatedVideoURL,
                videoGravity: gravity,
                autoplay: autoplaysGeneratedVideo
            )
            .accessibilityIdentifier("generated-video-player")
        } else if let template {
            TemplateMediaView(item: template, gravity: gravity)
        } else if let videoName {
            LoopingVideoView(resourceName: videoName, videoGravity: gravity)
        } else {
            Color.black
        }
    }

    private func pollGenerationTask(
        _ taskID: String,
        progressRecordID: UUID?
    ) async {
        let maximumAttempts = 100
        for attempt in 0..<maximumAttempts {
            guard !Task.isCancelled else { return }
            do {
                let task = try await PhotoReviveAPIClient.shared.generationTask(id: taskID)
                if task.status == "completed", let resultURL = task.resultURL {
                    generatedVideoURL = resultURL
                    BackgroundGenerationWorkStore.shared.markCompleted(
                        recordID: progressRecordID,
                        resultURL: resultURL
                    )
                    await AppAccountStore.shared.refreshHistory()
                    BackgroundGenerationWorkStore.shared.reconcile(
                        with: AppAccountStore.shared.historyTasks
                    )
                    AppAnalytics.generationCompleted(
                        contentType: "video",
                        itemID: template?.id,
                        elapsedMilliseconds: pollingElapsedMilliseconds
                    )
                    withAnimation(.easeInOut(duration: 0.24)) {
                        stage = .result
                    }
                    return
                }
                if task.status == "failed" {
                    // get-task performs the server-side failure refund before
                    // returning. Refresh the wallet so the UI never keeps the
                    // pre-refund balance after a failed generation.
                    let message = task.userFacingErrorMessage(
                        fallback: "The model could not generate this video. Please try again."
                    )
                    BackgroundGenerationWorkStore.shared.markFailed(
                        recordID: progressRecordID,
                        message: message
                    )
                    await AppAccountStore.shared.refreshCredits()
                    await AppAccountStore.shared.refreshHistory()
                    BackgroundGenerationWorkStore.shared.reconcile(
                        with: AppAccountStore.shared.historyTasks
                    )
                    AppAnalytics.generationFailed(
                        contentType: "video",
                        itemID: template?.id,
                        stage: "processing",
                        failureType: "server_task",
                        elapsedMilliseconds: pollingElapsedMilliseconds
                    )
                    stage = .failed(message)
                    return
                }
            } catch {
                // A brief connection failure should not discard a task that is
                // still running on the server. Surface it only after retries.
                if attempt == maximumAttempts - 1 {
                    let message = error.userFacingEnglishMessage(
                        fallback: "Unable to check the video status. Please try again."
                    )
                    BackgroundGenerationWorkStore.shared.markFailed(
                        recordID: progressRecordID,
                        message: message
                    )
                    AppAnalytics.generationFailed(
                        contentType: "video",
                        itemID: template?.id,
                        stage: "polling",
                        failureType: AppAnalytics.apiFailureType(error),
                        elapsedMilliseconds: pollingElapsedMilliseconds
                    )
                    stage = .failed(message)
                    return
                }
            }

            try? await Task.sleep(for: .seconds(3))
        }

        guard !Task.isCancelled else { return }
        AppAnalytics.generationFailed(
            contentType: "video",
            itemID: template?.id,
            stage: "polling",
            failureType: "timeout",
            elapsedMilliseconds: pollingElapsedMilliseconds
        )
        await AppAccountStore.shared.refreshHistory()
        stage = .failed("Generation is taking longer than expected. You can check it later in My Creations.")
    }

    private var pollingElapsedMilliseconds: Int {
        max(0, Int(Date().timeIntervalSince(pollingStartedAt) * 1_000))
    }

    private var exportSourceURL: URL? {
        if let generatedVideoURL { return generatedVideoURL }
        guard let videoName else { return nil }
        return ["mp4", "mov", "m4v"]
            .lazy
            .compactMap { Bundle.main.url(forResource: videoName, withExtension: $0) }
            .first
    }

    private func saveVideo() {
        guard !isExporting, let exportSourceURL else {
            exportError = GeneratedMediaExportError.mediaUnavailable.localizedDescription
            return
        }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let fileURL = try await GeneratedMediaExporter.prepareVideo(
                    from: exportSourceURL,
                    addsWatermark: !isSubscribed
                )
                try await GeneratedMediaExporter.saveVideo(at: fileURL)
                AppAnalytics.contentSaved(contentType: "video", itemID: template?.id)
                stage = .saved
            } catch {
                exportError = error.userFacingEnglishMessage(
                    fallback: "The video could not be saved. Please try again."
                )
            }
        }
    }

    private func shareVideo() {
        guard !isExporting, let exportSourceURL else {
            exportError = GeneratedMediaExportError.mediaUnavailable.localizedDescription
            return
        }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                shareURL = try await GeneratedMediaExporter.prepareVideo(
                    from: exportSourceURL,
                    addsWatermark: !isSubscribed
                )
                showShareSheet = true
            } catch {
                exportError = error.userFacingEnglishMessage(
                    fallback: "The video could not be shared. Please try again."
                )
            }
        }
    }

    private func deleteGeneration() {
        guard !isDeleting else { return }
        guard let taskID = submittedTaskID ?? taskID else {
            onClose()
            return
        }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await AppAccountStore.shared.deleteHistoryTask(id: taskID)
                onClose()
            } catch {
                exportError = error.userFacingEnglishMessage(
                    fallback: "The creation could not be deleted. Please try again."
                )
            }
        }
    }
}

private struct VideoGenerationPreviewView: View {
    let videoName: String?
    let template: TemplateItem?
    let generatedVideoURL: URL?
    let onClose: () -> Void
    let onRegenerate: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onRemoveWatermark: () -> Void
    @AppStorage("isSubscribed") private var isSubscribed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            previewMedia
                .ignoresSafeArea(edges: .horizontal)

            GeneratedContentWatermark()
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(.black.opacity(0.46), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.66), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close video preview")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()
            }

            HStack {
                Spacer()
                VStack(spacing: 17) {
                    previewAction("arrow.clockwise", label: "Regenerate", action: onRegenerate)
                    previewAction("arrow.down.to.line", label: "Save generated video", action: onSave)
                    if !isSubscribed {
                        previewAction("eraser", label: "Remove watermark", action: onRemoveWatermark)
                    }
                    previewAction("square.and.arrow.up", label: "Share generated video", accent: true, action: onShare)
                }
                .padding(.trailing, 20)
            }
            .padding(.top, 160)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var previewMedia: some View {
        if let generatedVideoURL {
            GeneratedVideoPlayerView(
                url: generatedVideoURL,
                videoGravity: .resizeAspect,
                autoplay: true
            )
            .accessibilityIdentifier("generated-video-player-fullscreen")
        } else if let template {
            TemplateMediaView(item: template, gravity: .resizeAspect)
        } else if let videoName {
            LoopingVideoView(resourceName: videoName, videoGravity: .resizeAspect)
        } else {
            Color.black
        }
    }

    private func previewAction(
        _ icon: String,
        label: String,
        accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 57, height: 57)
                .background(accent ? AppPalette.accent : Color.black.opacity(0.48), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct VideoGenerationDots: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 15) {
            dot(size: 8, delay: 0.0)
            dot(size: 15, delay: 0.12)
            dot(size: 24, delay: 0.24)
            dot(size: 15, delay: 0.36)
            dot(size: 8, delay: 0.48)
        }
        .onAppear { isAnimating = true }
    }

    private func dot(size: CGFloat, delay: Double) -> some View {
        Circle()
            .fill(.white)
            .frame(width: size, height: size)
            .offset(y: isAnimating ? -7 : 7)
            .animation(
                .easeInOut(duration: 0.68)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: isAnimating
            )
    }
}

private struct VideoShareIcon: View {
    let symbol: String
    let color: Color
    let label: String
    var size: CGFloat = 45
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: max(17, size * 0.47), weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(color, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct FixedFeatureView: View {
    let feature: FixedFeature
    let quickActions: [HomeQuickAction]
    let creditPricing: AppCreditPricing
    var imageRecommendationItems: [TemplateItem] = []
    @Binding var credits: Int

    private var photoToVideoCover: TemplateItem? {
        FixedFeatureCoverResolver.item(for: .photoToVideo, in: quickActions)
    }

    private var textToVideoCover: TemplateItem? {
        FixedFeatureCoverResolver.item(for: .textToVideo, in: quickActions)
    }

    private func generationTarget(for feature: FixedFeature) -> FeatureGenerationTarget? {
        quickActions.first { $0.feature == feature }?.generationTarget
    }

    private func generationTarget(
        for feature: FixedFeature,
        endpoint: String
    ) -> FeatureGenerationTarget? {
        FixedFeatureGenerationTargetResolver.target(
            for: feature,
            endpoint: endpoint,
            in: quickActions
        )
    }

    var body: some View {
        switch feature {
        case .oneTapRestore:
            FixedPhotoRestoreFeature(
                kind: .restore,
                coverItem: FixedFeatureCoverResolver.item(for: .oneTapRestore, in: quickActions),
                cost: creditPricing.oneTapRestoreCredits,
                generationTarget: generationTarget(for: .oneTapRestore),
                recommendationItems: imageRecommendationItems,
                photoToVideoGenerationTarget: generationTarget(for: .photoToVideo),
                credits: $credits
            )
        case .enhancePhoto:
            FixedPhotoRestoreFeature(
                kind: .enhance,
                coverItem: FixedFeatureCoverResolver.item(for: .enhancePhoto, in: quickActions),
                cost: creditPricing.enhancePhotoCredits,
                generationTarget: generationTarget(for: .enhancePhoto),
                recommendationItems: imageRecommendationItems,
                photoToVideoGenerationTarget: generationTarget(for: .photoToVideo),
                credits: $credits
            )
        case .photoToVideo:
            FixedVideoGeneratorFeature(
                initialMode: .image,
                creditPricing: creditPricing,
                credits: $credits,
                imageCoverItem: photoToVideoCover,
                textCoverItem: textToVideoCover,
                imageGenerationTarget: generationTarget(for: .photoToVideo),
                textGenerationTarget: generationTarget(for: .textToVideo)
            )
        case .textToVideo:
            FixedVideoGeneratorFeature(
                initialMode: .text,
                creditPricing: creditPricing,
                credits: $credits,
                imageCoverItem: photoToVideoCover,
                textCoverItem: textToVideoCover,
                imageGenerationTarget: generationTarget(for: .photoToVideo),
                textGenerationTarget: generationTarget(for: .textToVideo)
            )
        case .aiImage:
            FixedAIImageFeature(
                creditPricing: creditPricing,
                credits: $credits,
                recommendationItems: imageRecommendationItems,
                photoToVideoGenerationTarget: generationTarget(for: .photoToVideo),
                imageGenerationTarget: generationTarget(for: .aiImage, endpoint: "image-to-image"),
                textGenerationTarget: generationTarget(for: .aiImage, endpoint: "text-to-image")
            )
        case .imageToImage:
            FixedAIImageFeature(
                creditPricing: creditPricing,
                credits: $credits,
                initialMode: .image,
                recommendationItems: imageRecommendationItems,
                photoToVideoGenerationTarget: generationTarget(for: .photoToVideo),
                imageGenerationTarget: generationTarget(for: .imageToImage, endpoint: "image-to-image")
            )
        case .textToImage:
            FixedAIImageFeature(
                creditPricing: creditPricing,
                credits: $credits,
                initialMode: .text,
                recommendationItems: imageRecommendationItems,
                photoToVideoGenerationTarget: generationTarget(for: .photoToVideo),
                textGenerationTarget: generationTarget(for: .textToImage, endpoint: "text-to-image")
            )
        }
    }
}

enum FixedFeatureCoverResolver {
    static func item(
        for feature: FixedFeature,
        in quickActions: [HomeQuickAction]
    ) -> TemplateItem? {
        guard let item = quickActions.first(where: { $0.feature == feature })?.item,
              item.comparisonCover != nil
                || item.coverImageURL != nil
                || item.coverVideoURL != nil
                || !item.imageName.isEmpty
                || item.videoName != nil else {
            return nil
        }
        return item
    }
}

private struct FixedFeatureHeader: View {
    let title: String
    let showsHelp: Bool
    let onBack: () -> Void
    let onHelp: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack {
                Button(action: onBack) {
                    FixedFeatureHeaderIcon(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("fixed-feature-back-button")

                Spacer(minLength: 0)

                if showsHelp {
                    Button(action: onHelp) {
                        FixedFeatureHeaderIcon(systemName: "questionmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Help")
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 0)
        .padding(.bottom, 4)
    }
}

private struct FixedFeatureHeaderIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppPalette.ink.opacity(0.88))
            .frame(width: 38, height: 38)
            .background(Color.white.opacity(0.46), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
            .frame(width: 44, height: 44)
    }
}

private struct FixedFeatureScaffold<Content: View, Footer: View>: View {
    let title: String
    let showsHelp: Bool
    let onBack: () -> Void
    let onHelp: () -> Void
    let content: (CGSize) -> Content
    let footer: Footer

    init(
        title: String,
        showsHelp: Bool = false,
        onBack: @escaping () -> Void,
        onHelp: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (CGSize) -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.showsHelp = showsHelp
        self.onBack = onBack
        self.onHelp = onHelp
        self.content = content
        self.footer = footer()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PaperTextureBackground()

                VStack(spacing: 0) {
                    FixedFeatureHeader(
                        title: title,
                        showsHelp: showsHelp,
                        onBack: onBack,
                        onHelp: onHelp
                    )
                    .frame(width: proxy.size.width)
                    .zIndex(1)

                    GeometryReader { contentProxy in
                        let contentSize = CGSize(
                            width: max(0, contentProxy.size.width - 40),
                            height: max(0, contentProxy.size.height)
                        )

                        content(contentSize)
                            .frame(
                                width: contentSize.width,
                                height: contentSize.height,
                                alignment: .topLeading
                            )
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .top
                            )
                    }
                    .clipped()

                    footer
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                        .frame(width: proxy.size.width)
                        .background(.ultraThinMaterial.opacity(0.32))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .preferredColorScheme(.light)
    }
}

private enum FixedPhotoFeatureKind {
    case restore
    case enhance

    var title: String {
        switch self {
        case .restore: "AI One-Tap Restore"
        case .enhance: "AI Enhance"
        }
    }

    var tipsTitle: String {
        switch self {
        case .restore: "AI One-Tap Restore Tips"
        case .enhance: "AI Enhance Tips"
        }
    }

    var featureCardImageName: String {
        switch self {
        case .restore: "RestoreFeatureCard"
        case .enhance: "EnhanceFeatureCard"
        }
    }

    var recommendedTip: (subtitle: String, names: [String]) {
        switch self {
        case .restore: ("Damaged, faded, or blurry photo", ["RestoreTip1", "RestoreTip2"])
        case .enhance: ("Blurry or unclear photo", ["EnhanceTip1", "EnhanceTip2"])
        }
    }

    var avoidTip: (subtitle: String, names: [String]) {
        switch self {
        case .restore: ("Clear Photo", ["RestoreTip3", "RestoreTip4"])
        case .enhance: ("Clear or damaged photos will not produce effective results", ["EnhanceTip3", "EnhanceTip4"])
        }
    }

}

private struct FixedPhotoRestoreFeature: View {
    let kind: FixedPhotoFeatureKind
    let coverItem: TemplateItem?
    let cost: Int
    let generationTarget: FeatureGenerationTarget?
    let recommendationItems: [TemplateItem]
    let photoToVideoGenerationTarget: FeatureGenerationTarget?
    @Binding var credits: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selectedImage: UIImage?
    @State private var showPhotoSelection = false
    @State private var showTips = false
    @State private var showCredits = false
    @State private var showDraftWarning = false
    @State private var showCrop = false
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generatedImageURL: URL?
    @State private var generationTaskID: String?
    @State private var pendingImageGeneration: PendingImageGenerationRequest?
    @State private var showGenerationFlow = false

    var body: some View {
        ZStack {
            FixedFeatureScaffold(
                title: kind.title,
                showsHelp: true,
                onBack: requestDismiss,
                onHelp: { showTips = true }
            ) { contentSize in
                let layout = FixedPhotoUploadLayout(viewportSize: contentSize)

                VStack(alignment: .leading, spacing: layout.spacing) {
                    Button {
                        showPhotoSelection = true
                    } label: {
                        ZStack(alignment: .bottom) {
                            if selectedImage == nil {
                                if let coverItem {
                                    // The Home shortcut and its destination use
                                    // the exact same CMS item and media URLs.
                                    // This is a separate player instance because
                                    // the destination is a separate view hierarchy.
                                    FrostedTemplatePreview(item: coverItem)
                                } else {
                                    Image(kind.featureCardImageName)
                                        .resizable()
                                        .scaledToFill()
                                }
                            } else {
                                restorePreview
                            }

                            if selectedImage != nil || coverItem != nil {
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.42)],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )

                                HStack(spacing: 12) {
                                    FeatureAddPhotoIcon()
                                        .frame(width: 31, height: 31)
                                    Text(selectedImage == nil ? "Choose Photo" : "Change Photo")
                                        .font(.system(size: 21, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 25)
                                .frame(height: 54)
                                .background(.black.opacity(0.40), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.82), lineWidth: 1.5))
                                .padding(.bottom, 20)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: layout.previewHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fixed-photo-upload-preview")
                    .overlay(alignment: .bottomTrailing) {
                        if selectedImage != nil {
                            Button {
                                showCrop = true
                            } label: {
                                Image(systemName: "crop")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .padding(14)
                            .accessibilityLabel("Edit uploaded photo")
                        }
                    }

                    Text(kind.tipsTitle)
                        .font(.system(size: layout.titleFontSize, weight: .heavy))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(height: layout.titleHeight, alignment: .leading)

                    FeatureTipRow(
                        kind: kind,
                        imageHeight: layout.tipImageHeight,
                        iconSize: layout.tipIconSize,
                        spacing: layout.tipSpacing
                    )
                    .accessibilityIdentifier("fixed-photo-tip-row")
                }
                .frame(height: contentSize.height, alignment: .top)
            } footer: {
                FeaturePrimaryButton(
                    title: isGenerating ? "Generating…" : "Generate",
                    cost: cost,
                    credits: $credits,
                    onNeedCredits: { showCredits = true },
                    onCreate: startGeneration
                )
                .disabled(isGenerating)
            }

            if showTips {
                FeatureTipOverlay(kind: kind, onDismiss: { showTips = false })
                    .transition(.opacity)
                    .zIndex(2)
            }

            if showDraftWarning {
                FeatureDraftWarningOverlay(
                    onConfirm: { dismiss() },
                    onCancel: { showDraftWarning = false }
                )
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .fullScreenCover(isPresented: $showCredits) {
            CreditCenterView(credits: $credits)
        }
        .sheet(isPresented: $showPhotoSelection) {
            PhotoSelectionSheet { images in
                selectedImage = images.first
            }
            .presentationDetents([.fraction(0.73), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(30)
        }
        .fullScreenCover(isPresented: $showCrop) {
            if let selectedImage {
                FeaturePhotoCropView(image: selectedImage) { editedImage in
                    self.selectedImage = editedImage
                }
            }
        }
        .fullScreenCover(isPresented: $showGenerationFlow) {
            if let pendingImageGeneration {
                ImageGenerationFlowView(
                    title: kind.title,
                    template: resultTemplate,
                    generatedImageURL: generatedImageURL,
                    taskID: generationTaskID,
                    loadingPreviewImage: selectedImage,
                    submissionAction: {
                        try await pendingImageGeneration.submit()
                    },
                    onSubmission: { submission in
                        credits = submission.creditsBalance
                        generatedImageURL = submission.resultURL
                        generationTaskID = submission.taskID
                        isGenerating = false
                    },
                    recommendationItems: recommendationItems,
                    photoToVideoGenerationTarget: photoToVideoGenerationTarget,
                    credits: $credits,
                    onRegenerate: closeGenerationFlow,
                    onClose: {
                        closeGenerationFlow()
                        dismiss()
                    }
                )
            } else {
                ImageGenerationFlowView(
                    title: kind.title,
                    template: resultTemplate,
                    generatedImageURL: generatedImageURL,
                    taskID: generationTaskID,
                    loadingPreviewImage: selectedImage,
                    recommendationItems: recommendationItems,
                    photoToVideoGenerationTarget: photoToVideoGenerationTarget,
                    credits: $credits,
                    onRegenerate: closeGenerationFlow,
                    onClose: {
                        closeGenerationFlow()
                        dismiss()
                    }
                )
            }
        }
        .alert(
            "Generation unavailable",
            isPresented: Binding(
                get: { generationError != nil },
                set: { if !$0 { generationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { generationError = nil }
        } message: {
            Text(generationError ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var restorePreview: some View {
        if let selectedImage {
            FrostedUploadedPhoto(image: selectedImage)
        } else {
            Image(kind.featureCardImageName)
                .resizable()
                .scaledToFill()
        }
    }

    private func requestDismiss() {
        if selectedImage != nil {
            showDraftWarning = true
        } else {
            dismiss()
        }
    }

    private var resultTemplate: TemplateItem {
        TemplateItem(
            id: generationTarget?.itemID ?? "unconfigured-\(kind.title)",
            title: kind.title,
            generationKind: .image,
            estimatedCredits: cost,
            modelType: generationTarget?.modelType,
            modelID: generationTarget?.modelID
        )
    }

    private func startGeneration() {
        guard !isGenerating else { return }
        guard let selectedImage else {
            generationError = "Please choose a source photo."
            return
        }
        guard let generationTarget else {
            generationError = "This feature has not been connected to a CMS generation template yet."
            return
        }
        guard generationTarget.endpoint == "image-to-image" else {
            generationError = "The CMS generation target for this feature is invalid."
            return
        }

        generationError = nil
        generatedImageURL = nil
        generationTaskID = nil
        pendingImageGeneration = PendingImageGenerationRequest(
            endpoint: .imageToImage,
            itemID: generationTarget.itemID,
            images: [selectedImage],
            prompt: nil,
            options: PhotoReviveImageGenerationOptions(
                resolution: PhotoReviveImageGenerationOptions.providerDefaultResolution,
                // Restore/enhance should preserve the uploaded photo's
                // composition instead of forcing a generation ratio.
                aspectRatio: nil,
                outputCount: 1
            )
        )
        isGenerating = true
        showGenerationFlow = true
    }

    private func closeGenerationFlow() {
        showGenerationFlow = false
        isGenerating = false
        pendingImageGeneration = nil
    }
}

private struct FeatureTipRow: View {
    let kind: FixedPhotoFeatureKind
    var imageHeight: CGFloat = 76
    var iconSize: CGFloat = 25
    var spacing: CGFloat = 8

    private var items: [(String, String, Bool)] {
        switch kind {
        case .restore:
            [("RestoreTip1", "", true), ("RestoreTip2", "", true), ("RestoreTip3", "", false), ("RestoreTip4", "", false)]
        case .enhance:
            [("EnhanceTip1", "", true), ("EnhanceTip2", "", true), ("EnhanceTip3", "", false), ("EnhanceTip4", "", false)]
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: spacing) {
                    Image(item.0)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: imageHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    Image(systemName: item.2 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: iconSize, weight: .bold))
                        .foregroundStyle(item.2 ? Color(red: 0.58, green: 0.69, blue: 0.40) : Color(red: 0.84, green: 0.24, blue: 0.20))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct FeatureTipOverlay: View {
    let kind: FixedPhotoFeatureKind
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = min(max(proxy.size.width - 34, 0), 360)
            let imageSize = min(max((cardWidth - 124) / 2, 76), 92)

            ZStack {
                Color.black.opacity(0.46)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Text(kind.tipsTitle)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                        .accessibilityIdentifier("feature-tips-title")
                        .padding(.bottom, 30)

                    tipSection(
                        title: "Recommended",
                        subtitle: kind.recommendedTip.subtitle,
                        names: kind.recommendedTip.names,
                        color: Color(red: 0.58, green: 0.69, blue: 0.40),
                        icon: "checkmark.circle.fill",
                        imageSize: imageSize
                    )

                    tipSection(
                        title: "Not Recommended",
                        subtitle: kind.avoidTip.subtitle,
                        names: kind.avoidTip.names,
                        color: Color(red: 0.88, green: 0.26, blue: 0.20),
                        icon: "xmark.circle.fill",
                        imageSize: imageSize
                    )
                    .padding(.top, 28)

                    Button(action: onDismiss) {
                        Text("Continue")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.88, blue: 0.62))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(.black.opacity(0.92), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("feature-tips-continue")
                    .padding(.top, 24)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(width: cardWidth)
                .background(.white, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            }
        }
    }

    private func tipSection(
        title: String,
        subtitle: String,
        names: [String],
        color: Color,
        icon: String,
        imageSize: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Label(title, systemImage: icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(color)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.88)
                .padding(.top, 14)

            HStack(spacing: 32) {
                ForEach(names, id: \.self) { name in
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .frame(width: imageSize, height: imageSize)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("feature-tip-\(name)")
                }
            }
            .padding(.top, 16)
        }
    }
}

private struct FeaturePrimaryButton: View {
    let title: String
    let cost: Int
    @Binding var credits: Int
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    let onNeedCredits: () -> Void
    let onCreate: () -> Void
    @State private var showLogin = false
    @State private var pendingLoginAction: (() -> Void)?

    var body: some View {
        Button {
            requireLogin {
                guard cost == 0 || credits >= cost else {
                    onNeedCredits()
                    return
                }
                onCreate()
            }
        } label: {
            ZStack {
                VStack(spacing: 0) {
                    Text(cost > 0 && credits < cost ? "More Credits" : title)
                        .font(.system(size: 26, weight: .heavy))
                    if cost > 0 && credits < cost {
                        Text("Not enough credits")
                            .font(.system(size: 13, weight: .regular))
                    }
                }

                HStack {
                    Spacer()
                    if cost > 0 {
                        HStack(spacing: 5) {
                            Image("RewardsCreditToken")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text("\(cost)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.yellow)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 19)
            .frame(maxWidth: .infinity)
            .frame(height: 63)
            .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppPalette.ink, lineWidth: 1.2))
        }
        .buttonStyle(TemplatePressStyle())
        .accessibilityIdentifier("fixed-feature-primary-action")
        .fullScreenCover(isPresented: $showLogin, onDismiss: {
            if !isLoggedIn { pendingLoginAction = nil }
        }) {
            SignInView {
                showLogin = false
                let action = pendingLoginAction
                pendingLoginAction = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: action ?? {})
            }
        }
    }

    private func requireLogin(_ action: @escaping () -> Void) {
        guard isLoggedIn || ProcessInfo.processInfo.arguments.contains("-loggedIn") else {
            pendingLoginAction = action
            AppAnalytics.authGateShown(source: "fixed_feature_generation")
            showLogin = true
            return
        }
        action()
    }
}

private struct FeatureDraftWarningOverlay: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()

            ZStack(alignment: .top) {
                VStack(spacing: 16) {
                    Text("Your draft won't be saved if you leave.")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(AppPalette.brownInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onConfirm) {
                        Text("Confirm")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 57)
                            .background(Color(red: 1.0, green: 0.20, blue: 0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.gray)
                            .frame(minHeight: 30)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.top, 60)
                .padding(.bottom, 20)
                .background(
                    LinearGradient(colors: [Color.white, Color(red: 1, green: 0.94, blue: 0.80)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AppPalette.surfaceEdge, lineWidth: 4))

                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.97, blue: 0.89))

                    Image(systemName: "bell.fill")
                        .font(.system(size: 39, weight: .semibold))
                        .foregroundStyle(Color(red: 0.98, green: 0.71, blue: 0.29))
                }
                .frame(width: 88, height: 88)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.92), lineWidth: 3)
                )
                .shadow(color: AppPalette.brownInk.opacity(0.18), radius: 8, y: 4)
                .offset(y: -44)
                .accessibilityHidden(true)
            }
            .padding(.top, 44)
            .padding(.horizontal, 54)
        }
    }
}

private enum FixedVideoGeneratorMode: Hashable {
    case image
    case text
}

private struct FixedVideoGeneratorFeature: View {
    let initialMode: FixedVideoGeneratorMode
    let creditPricing: AppCreditPricing
    let imageCoverItem: TemplateItem?
    let textCoverItem: TemplateItem?
    let imageGenerationTarget: FeatureGenerationTarget?
    let textGenerationTarget: FeatureGenerationTarget?
    @Binding var credits: Int
    @Environment(\.dismiss) private var dismiss
    @State private var mode: FixedVideoGeneratorMode
    @State private var selectedImage: UIImage?
    @State private var showPhotoSelection = false
    @State private var prompt = ""
    @State private var showSettings = false
    @State private var showCredits = false
    @State private var showDraftWarning = false
    @State private var showCrop = false
    @State private var soundEnabled = false
    @State private var multiShotEnabled = false
    @State private var duration = "5s"
    @State private var resolution = "480p"
    @State private var ratio = "9:16"
    @State private var showGenerationFlow = false
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generationTaskID: String?
    @State private var pendingVideoGeneration: PendingVideoGenerationRequest?

    init(
        initialMode: FixedVideoGeneratorMode,
        creditPricing: AppCreditPricing = .defaultValue,
        credits: Binding<Int>,
        initialImage: UIImage? = nil,
        imageCoverItem: TemplateItem? = nil,
        textCoverItem: TemplateItem? = nil,
        imageGenerationTarget: FeatureGenerationTarget? = nil,
        textGenerationTarget: FeatureGenerationTarget? = nil
    ) {
        self.initialMode = initialMode
        self.creditPricing = creditPricing
        self.imageCoverItem = imageCoverItem
        self.textCoverItem = textCoverItem
        self.imageGenerationTarget = imageGenerationTarget
        self.textGenerationTarget = textGenerationTarget
        _credits = credits
        _mode = State(initialValue: initialMode)
        _selectedImage = State(initialValue: initialImage)
        _soundEnabled = State(initialValue: creditPricing.defaultVideoSound)
        _multiShotEnabled = State(initialValue: creditPricing.defaultVideoMultiShot)
        _duration = State(initialValue: "\(creditPricing.videoDefaultDurationSeconds)s")
        _resolution = State(initialValue: creditPricing.defaultVideoResolution)
    }

    private var activeCoverItem: TemplateItem? {
        mode == .image ? imageCoverItem : textCoverItem
    }

    var body: some View {
        ZStack {
            FixedFeatureScaffold(
                title: "Video Generator",
                showsHelp: true,
                onBack: requestDismiss
            ) { contentSize in
                let layout = FixedVideoUploadLayout(viewportSize: contentSize)

                VStack(alignment: .leading, spacing: layout.spacing) {
                    FeatureModeTabs(
                        options: [("Image to Video", .image), ("Text To Video", .text)],
                        selection: $mode
                    )
                    .frame(height: layout.tabsHeight)

                    if mode == .image {
                        Button {
                            showPhotoSelection = true
                        } label: {
                            FeatureVideoGeneratorPreview(
                                image: selectedImage,
                                template: imageCoverItem,
                                showsChoosePhoto: selectedImage == nil,
                                prompt: selectedImage == nil
                                    ? ""
                                    : prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                                height: layout.previewHeight
                            )
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottomTrailing) {
                            if selectedImage != nil {
                                Button { showCrop = true } label: {
                                    Image(systemName: "crop")
                                        .foregroundStyle(.white)
                                        .frame(width: 40, height: 40)
                                        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .padding(14)
                            }
                        }
                    } else {
                        FeatureVideoGeneratorPreview(
                            image: nil,
                            template: textCoverItem,
                            showsChoosePhoto: false,
                            prompt: "",
                            height: layout.previewHeight
                        )
                    }

                    FeaturePromptBox(
                        text: $prompt,
                        placeholder: mode == .image ? "Describe motion you want to add to your photo" : "Describe your video vision here",
                        height: layout.promptHeight
                    )

                    FeatureSettingsSummary(
                        values: videoSettingsSummaryValues,
                        onTap: { showSettings = true }
                    )
                    .frame(height: layout.settingsHeight)
                }
                .frame(height: contentSize.height, alignment: .top)
            } footer: {
                FeaturePrimaryButton(
                    title: isGenerating ? "Generating…" : "Generate",
                    cost: generationCost,
                    credits: $credits,
                    onNeedCredits: { showCredits = true },
                    onCreate: startGeneration
                )
                .disabled(isGenerating)
            }

            if showDraftWarning {
                FeatureDraftWarningOverlay(onConfirm: { dismiss() }, onCancel: { showDraftWarning = false })
                    .zIndex(2)
            }
        }
        .sheet(isPresented: $showPhotoSelection) {
            PhotoSelectionSheet { images in
                selectedImage = images.first
            }
            .presentationDetents([.fraction(0.73), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(30)
        }
        .sheet(isPresented: $showSettings) {
            FeatureSettingsSheet(
                mode: .video,
                videoCapabilities: videoCapabilities,
                imageCapabilities: .conservativeFallback,
                soundEnabled: $soundEnabled,
                multiShotEnabled: $multiShotEnabled,
                duration: $duration,
                resolution: $resolution,
                ratio: $ratio,
                outputCount: .constant("1")
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showCredits) { CreditCenterView(credits: $credits) }
        .fullScreenCover(isPresented: $showGenerationFlow) {
            if let pendingVideoGeneration {
                VideoGenerationFlowView(
                    title: "Video Generator",
                    templateTitle: mode == .image ? "Photo To Video" : "Text To Video",
                    videoName: nil,
                    template: activeCoverItem,
                    loadingPreviewImage: selectedImage,
                    submissionAction: {
                        try await pendingVideoGeneration.submit()
                    },
                    onSubmission: { submission in
                        credits = submission.creditsBalance
                        generationTaskID = submission.taskID
                        isGenerating = false
                    },
                    onRegenerate: closeGenerationFlow,
                    onClose: closeGenerationFlow
                )
            }
        }
        .fullScreenCover(isPresented: $showCrop) {
            if let selectedImage {
                FeaturePhotoCropView(image: selectedImage) { editedImage in
                    self.selectedImage = editedImage
                }
            }
        }
        .alert(
            "Generation unavailable",
            isPresented: Binding(
                get: { generationError != nil },
                set: { if !$0 { generationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { generationError = nil }
        } message: {
            Text(generationError ?? "Please try again.")
        }
        .onChange(of: mode) { _, _ in
            applyVideoCapabilities()
        }
    }

    private var generationCost: Int {
        let normalizedDuration = videoCapabilities.normalizedDuration(duration)
        let normalizedResolution = videoCapabilities.normalizedResolution(resolution)
        let seconds = Int(normalizedDuration.trimmingCharacters(in: CharacterSet.decimalDigits.inverted))
            ?? creditPricing.videoDefaultDurationSeconds
        return creditPricing.videoGenerationCredits(
            duration: seconds,
            resolution: normalizedResolution,
            sound: videoCapabilities.supportsSound && soundEnabled,
            multiShot: videoCapabilities.supportsMultiShot && multiShotEnabled
        )
    }

    private func requestDismiss() {
        if selectedImage != nil || !prompt.isEmpty { showDraftWarning = true } else { dismiss() }
    }

    private var activeGenerationTarget: FeatureGenerationTarget? {
        mode == .image ? imageGenerationTarget : textGenerationTarget
    }

    private var videoCapabilities: VideoGenerationOptionCapabilities {
        .current(forModelID: activeGenerationTarget?.modelID)
    }

    private var videoSettingsSummaryValues: [String] {
        var values: [String] = []
        if videoCapabilities.supportsSound {
            values.append(soundEnabled ? "sound" : "mute")
        }
        if videoCapabilities.supportsMultiShot {
            values.append(multiShotEnabled ? "multi" : "single")
        }
        values.append(contentsOf: [
            videoCapabilities.normalizedDuration(duration),
            videoCapabilities.normalizedResolution(resolution),
            videoCapabilities.normalizedAspectRatio(ratio),
        ])
        return values
    }

    private func applyVideoCapabilities() {
        duration = videoCapabilities.normalizedDuration(duration)
        resolution = videoCapabilities.normalizedResolution(resolution)
        ratio = videoCapabilities.normalizedAspectRatio(ratio)
        if !videoCapabilities.supportsSound { soundEnabled = false }
        if !videoCapabilities.supportsMultiShot { multiShotEnabled = false }
    }

    private func startGeneration() {
        guard !isGenerating else { return }
        guard let target = activeGenerationTarget else {
            generationError = "This feature has not been connected to a CMS generation template yet."
            return
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .image && selectedImage == nil {
            generationError = "Please choose a source photo."
            return
        }
        if mode == .text && trimmedPrompt.isEmpty && target.promptTemplate == nil {
            generationError = "Please describe the video you want to create."
            return
        }

        let normalizedDuration = videoCapabilities.normalizedDuration(duration)
        let normalizedResolution = videoCapabilities.normalizedResolution(resolution)
        let normalizedRatio = videoCapabilities.normalizedAspectRatio(ratio)
        let normalizedSound = videoCapabilities.supportsSound && soundEnabled
        let normalizedMultiShot = videoCapabilities.supportsMultiShot && multiShotEnabled
        let seconds = Int(normalizedDuration.trimmingCharacters(in: CharacterSet.decimalDigits.inverted))
            ?? creditPricing.videoDefaultDurationSeconds
        let options = PhotoReviveVideoGenerationOptions(
            resolution: normalizedResolution,
            aspectRatio: normalizedRatio,
            duration: seconds,
            sound: normalizedSound,
            multiShot: normalizedMultiShot
        )

        let endpoint: PendingVideoGenerationEndpoint
        let images: [UIImage]
        switch (mode, target.endpoint) {
        case (.image, "image-to-video"):
            guard let selectedImage else {
                generationError = "Please choose a source photo."
                return
            }
            endpoint = .imageToVideo
            images = [selectedImage]
        case (.text, "text-to-video"):
            endpoint = .textToVideo
            images = []
        default:
            generationError = "The CMS generation target for this feature is invalid."
            return
        }

        generationError = nil
        generationTaskID = nil
        pendingVideoGeneration = PendingVideoGenerationRequest(
            endpoint: endpoint,
            itemID: target.itemID,
            images: images,
            prompt: trimmedPrompt.isEmpty ? nil : trimmedPrompt,
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            options: options
        )
        isGenerating = true
        showGenerationFlow = true
    }

    private func closeGenerationFlow() {
        showGenerationFlow = false
        isGenerating = false
        pendingVideoGeneration = nil
    }
}

private struct FeatureVideoGeneratorPreview: View {
    let image: UIImage?
    let template: TemplateItem?
    let showsChoosePhoto: Bool
    let prompt: String
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let image {
                    FrostedUploadedPhoto(image: image)
                } else if let template {
                    TemplateMediaView(
                        item: template,
                        gravity: .resizeAspect,
                        imageContentMode: .fit,
                        fillsFitImageBackground: true,
                        aspectFitVideoBackgroundColor: UIColor(
                            red: 0.95,
                            green: 0.82,
                            blue: 0.64,
                            alpha: 1
                        )
                    )
                    .allowsHitTesting(false)
                } else {
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
                    }
                }
            }

            if showsChoosePhoto {
                Label("Choose Photo", systemImage: "photo.badge.plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 48)
                    .background(.black.opacity(0.48), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.84), lineWidth: 1.5))
                    .padding(.bottom, 14)
            }

            if !prompt.isEmpty {
                LinearGradient(colors: [.clear, .black.opacity(0.58)], startPoint: .center, endPoint: .bottom)

                Text(prompt)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 19)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppPalette.surfaceEdge.opacity(0.75), lineWidth: 1.2))
    }
}

private struct FeatureModeTabs<Selection: Hashable>: View {
    let options: [(String, Selection)]
    @Binding var selection: Selection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { entry in
                let option = entry.element
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = option.1 }
                } label: {
                    Text(option.0)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(selection == option.1 ? AppPalette.ink : .gray)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(selection == option.1 ? Color(red: 1, green: 0.76, blue: 0.36) : .clear, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feature-mode-\(option.0)")
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 15))
    }
}

private enum PromptEditorStyle {
    static let bodyColor = UIColor(
        red: 0.67,
        green: 0.68,
        blue: 0.70,
        alpha: 1
    )
    static let imageReferenceColor = UIColor(
        red: 0.76,
        green: 0.53,
        blue: 0.30,
        alpha: 1
    )
    static let imageReferenceBackgroundColor = UIColor(
        red: 1.00,
        green: 0.86,
        blue: 0.64,
        alpha: 0.36
    )

    static var bodyFont: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 18, weight: .regular)
        )
    }
}

private struct FeaturePromptBox: View {
    @Binding var text: String
    let placeholder: String
    var height: CGFloat = 152
    var isEditable = true
    var insertionRequest: PromptEditorInsertionRequest?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color(uiColor: PromptEditorStyle.bodyColor))
                    .padding(.horizontal, 18)
                    .padding(.top, 17)
            }

            ImageReferencePromptEditor(
                text: $text,
                isEditable: isEditable,
                characterLimit: 2000,
                insertionRequest: insertionRequest
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppPalette.surfaceEdge.opacity(0.72), lineWidth: 1.2))
    }
}

private struct PromptEditorInsertionRequest: Equatable {
    let id = UUID()
    let text: String
}

private extension NSAttributedString.Key {
    static let imageReferenceToken = NSAttributedString.Key("PhotoReviveImageReferenceToken")
}

/// Draws a rounded background behind `@ImageN` ranges without changing the raw
/// prompt sent to the generation API.
private final class ImageReferenceLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let textStorage, let textContainer = textContainers.first else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        let characterRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(
            .imageReferenceToken,
            in: characterRange,
            options: []
        ) { value, range, _ in
            guard value != nil else { return }
            let tokenGlyphRange = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateEnclosingRects(
                forGlyphRange: tokenGlyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                let tokenRect = rect
                    .offsetBy(dx: origin.x, dy: origin.y)
                    .insetBy(dx: -4, dy: -2)
                PromptEditorStyle.imageReferenceBackgroundColor.setFill()
                UIBezierPath(roundedRect: tokenRect, cornerRadius: 9).fill()
            }
        }

        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}

private struct ImageReferencePromptEditor: UIViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let characterLimit: Int
    let insertionRequest: PromptEditorInsertionRequest?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textStorage = NSTextStorage()
        let layoutManager = ImageReferenceLayoutManager()
        let textContainer = NSTextContainer(size: .zero)
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = UITextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 18, bottom: 38, right: 18)
        textView.isScrollEnabled = true
        textView.isSelectable = true
        textView.adjustsFontForContentSizeCategory = true
        context.coordinator.render(text, in: textView, preservingSelection: false)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        textView.isEditable = isEditable
        textView.accessibilityTraits = isEditable ? [.allowsDirectInteraction] : [.staticText]
        if let insertionRequest,
           context.coordinator.lastHandledInsertionID != insertionRequest.id {
            context.coordinator.lastHandledInsertionID = insertionRequest.id
            let updatedText = context.coordinator.insert(
                insertionRequest.text,
                in: textView
            )
            DispatchQueue.main.async {
                text = updatedText
            }
            return
        }
        if textView.attributedText.string != text {
            context.coordinator.render(text, in: textView, preservingSelection: true)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ImageReferencePromptEditor
        var lastHandledInsertionID: UUID?
        private var isRendering = false
        private let referenceRegex = try! NSRegularExpression(
            pattern: #"@Image\d+"#,
            options: [.caseInsensitive]
        )

        init(parent: ImageReferencePromptEditor) {
            self.parent = parent
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            let protectedRange = expandingToWholeImageReferences(
                range,
                in: textView.text ?? ""
            )
            if protectedRange != range {
                let rawText = textView.text ?? ""
                let next = (rawText as NSString).replacingCharacters(
                    in: protectedRange,
                    with: replacement
                )
                guard next.count <= parent.characterLimit else { return false }

                parent.text = next
                render(next, in: textView, preservingSelection: false)
                textView.selectedRange = NSRange(
                    location: protectedRange.location + (replacement as NSString).length,
                    length: 0
                )
                return false
            }

            guard let swiftRange = Range(range, in: textView.text) else { return false }
            let next = textView.text.replacingCharacters(in: swiftRange, with: replacement)
            return next.count <= parent.characterLimit
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isRendering, textView.selectedRange.length == 0 else { return }
            let location = textView.selectedRange.location
            let text = textView.text ?? ""
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            for match in referenceRegex.matches(in: text, range: fullRange) {
                let tokenRange = match.range
                if location > tokenRange.location, location < NSMaxRange(tokenRange) {
                    textView.selectedRange = NSRange(location: NSMaxRange(tokenRange), length: 0)
                    return
                }
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isRendering, textView.markedTextRange == nil else { return }
            let rawText = String(textView.text.prefix(parent.characterLimit))
            parent.text = rawText
            render(rawText, in: textView, preservingSelection: true)
        }

        func insert(_ insertedText: String, in textView: UITextView) -> String {
            let rawText = textView.text ?? ""
            let rawNSString = rawText as NSString
            let selection = textView.selectedRange
            let safeLocation = min(selection.location, rawNSString.length)
            let safeLength = min(selection.length, rawNSString.length - safeLocation)
            let safeSelection = expandingToWholeImageReferences(
                NSRange(location: safeLocation, length: safeLength),
                in: rawText
            )
            let updatedText = rawNSString.replacingCharacters(
                in: safeSelection,
                with: insertedText
            )

            guard updatedText.count <= parent.characterLimit else {
                textView.becomeFirstResponder()
                return rawText
            }

            render(updatedText, in: textView, preservingSelection: false)
            textView.selectedRange = NSRange(
                location: safeSelection.location + (insertedText as NSString).length,
                length: 0
            )
            textView.becomeFirstResponder()
            return updatedText
        }

        private func expandingToWholeImageReferences(
            _ proposedRange: NSRange,
            in text: String
        ) -> NSRange {
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            var expandedRange = proposedRange

            for match in referenceRegex.matches(in: text, range: fullRange) {
                let tokenRange = match.range
                let selectionIntersectsToken: Bool
                if proposedRange.length == 0 {
                    selectionIntersectsToken = proposedRange.location > tokenRange.location
                        && proposedRange.location < NSMaxRange(tokenRange)
                } else {
                    selectionIntersectsToken = NSIntersectionRange(
                        expandedRange,
                        tokenRange
                    ).length > 0
                }

                if selectionIntersectsToken {
                    expandedRange = NSUnionRange(expandedRange, tokenRange)
                }
            }

            return expandedRange
        }

        func render(_ rawText: String, in textView: UITextView, preservingSelection: Bool) {
            isRendering = true
            defer { isRendering = false }

            let selectedRange = textView.selectedRange
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 6
            let attributed = NSMutableAttributedString(
                string: rawText,
                attributes: [
                    .font: PromptEditorStyle.bodyFont,
                    .foregroundColor: PromptEditorStyle.bodyColor,
                    .paragraphStyle: paragraphStyle,
                ]
            )
            let fullRange = NSRange(location: 0, length: attributed.length)
            referenceRegex.enumerateMatches(in: rawText, range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                attributed.addAttributes([
                    .imageReferenceToken: true,
                    .foregroundColor: PromptEditorStyle.imageReferenceColor,
                ], range: range)
            }
            textView.attributedText = attributed
            if preservingSelection {
                let location = min(selectedRange.location, attributed.length)
                let length = min(selectedRange.length, attributed.length - location)
                textView.selectedRange = NSRange(location: location, length: length)
            }
        }
    }
}

private struct FeatureSettingsSummary: View {
    let values: [String]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    if value == "mute" {
                        Image(systemName: "speaker.slash.fill")
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.35), in: Circle())
                    } else if value == "sound" {
                        Image(systemName: "speaker.wave.2.fill")
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.35), in: Circle())
                    } else if value == "single" {
                        Image(systemName: "video.slash.fill")
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.35), in: Circle())
                    } else if value == "multi" {
                        Image(systemName: "video.badge.waveform.fill")
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.35), in: Circle())
                    } else {
                        Text(value)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppPalette.surfaceEdge)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 8)
                            .frame(height: 34)
                            .background(Color.white.opacity(0.35), in: Capsule())
                    }
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppPalette.surfaceEdge)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppPalette.surfaceEdge.opacity(0.72), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit output settings")
    }
}

struct ImageGenerationUploadView: View {
    let template: TemplateItem
    let creditPricing: AppCreditPricing
    let recommendationItems: [TemplateItem]
    let photoToVideoGenerationTarget: FeatureGenerationTarget?
    @Binding var credits: Int

    @Environment(\.dismiss) private var dismiss
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @AppStorage("hasAcceptedImageAIDataNotice") private var hasAcceptedDataNotice = false
    @State private var selectedImages: [UIImage?]
    @State private var showPhotoSelection = false
    @State private var resolution = PhotoReviveImageGenerationOptions.providerDefaultResolution
    @State private var ratio = "9:16"
    @State private var outputCount = "1"
    @State private var showSettings = false
    @State private var showCredits = false
    @State private var showDataNotice = false
    @State private var showGenerationFlow = false
    @State private var showLogin = false
    @State private var showCropIndex: Int?
    @State private var pendingLoginAction: (() -> Void)?
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generatedImageURL: URL?
    @State private var generationTaskID: String?
    @State private var pendingImageGeneration: PendingImageGenerationRequest?

    init(
        template: TemplateItem,
        creditPricing: AppCreditPricing = .defaultValue,
        credits: Binding<Int>,
        recommendationItems: [TemplateItem] = [],
        photoToVideoGenerationTarget: FeatureGenerationTarget? = nil
    ) {
        self.template = template
        self.creditPricing = creditPricing
        self.recommendationItems = recommendationItems
        self.photoToVideoGenerationTarget = photoToVideoGenerationTarget
        _credits = credits
        // Every upload slot starts empty. A template cover is a preview, not
        // an implicit user photo or clothing reference.
        _selectedImages = State(initialValue: Array(repeating: nil, count: template.imageUploadCount))
    }

    var body: some View {
        ZStack {
            FixedFeatureScaffold(
                title: template.title,
                showsHelp: false,
                onBack: { dismiss() }
            ) { contentSize in
                let layout = ImageTemplateUploadLayout(viewportSize: contentSize)

                VStack(alignment: .leading, spacing: layout.spacing) {
                    templatePreview(height: layout.previewHeight)

                    Text("Upload Image")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(AppPalette.ink)
                        .frame(height: layout.titleHeight, alignment: .leading)

                    uploadSlots(height: layout.uploadHeight)

                    FeatureSettingsSummary(
                        values: imageSettingsSummaryValues,
                        onTap: { showSettings = true }
                    )
                    .frame(height: layout.settingsHeight)
                }
                .frame(height: contentSize.height, alignment: .top)
                .accessibilityIdentifier("image-generation-upload")
            } footer: {
                ImageGenerationPrimaryButton(
                    cost: generationCost,
                    credits: credits,
                    isLoading: isGenerating,
                    action: beginGeneration
                )
                .accessibilityIdentifier("image-generate-button")
            }

            if showDataNotice {
                ImageAIDataProcessingNotice(
                    onAgree: acceptNoticeAndGenerate,
                    onCancel: { showDataNotice = false }
                )
                .zIndex(5)
            }
        }
        .sheet(isPresented: $showPhotoSelection) {
            PhotoSelectionSheet(maximumSelectionCount: template.imageUploadCount) { images in
                applySelectedImages(images)
            }
            .presentationDetents([.fraction(0.73), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(30)
        }
        .sheet(isPresented: $showSettings) {
            FeatureSettingsSheet(
                mode: .image,
                videoCapabilities: .conservativeFallback,
                imageCapabilities: imageCapabilities,
                soundEnabled: .constant(false),
                multiShotEnabled: .constant(false),
                duration: .constant("5s"),
                resolution: $resolution,
                ratio: $ratio,
                outputCount: $outputCount
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showGenerationFlow) {
            if let pendingImageGeneration {
                ImageGenerationFlowView(
                    title: template.title,
                    template: template,
                    generatedImageURL: generatedImageURL,
                    taskID: generationTaskID,
                    loadingPreviewImage: selectedImages.compactMap { $0 }.first,
                    submissionAction: {
                        try await pendingImageGeneration.submit()
                    },
                    onSubmission: { submission in
                        credits = submission.creditsBalance
                        generatedImageURL = submission.resultURL
                        generationTaskID = submission.taskID
                        isGenerating = false
                    },
                    recommendationItems: recommendationItems,
                    photoToVideoGenerationTarget: photoToVideoGenerationTarget,
                    credits: $credits,
                    onRegenerate: closeGenerationFlow,
                    onClose: {
                        closeGenerationFlow()
                        dismiss()
                    }
                )
            } else {
                ImageGenerationFlowView(
                    title: template.title,
                    template: template,
                    generatedImageURL: generatedImageURL,
                    taskID: generationTaskID,
                    loadingPreviewImage: selectedImages.compactMap { $0 }.first,
                    recommendationItems: recommendationItems,
                    photoToVideoGenerationTarget: photoToVideoGenerationTarget,
                    credits: $credits,
                    onRegenerate: closeGenerationFlow,
                    onClose: {
                        closeGenerationFlow()
                        dismiss()
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showCredits) {
            CreditCenterView(credits: $credits)
        }
        .fullScreenCover(isPresented: $showLogin, onDismiss: {
            if !isLoggedIn { pendingLoginAction = nil }
        }) {
            SignInView {
                showLogin = false
                let action = pendingLoginAction
                pendingLoginAction = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: action ?? {})
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { showCropIndex != nil },
                set: { if !$0 { showCropIndex = nil } }
            )
        ) {
            if let index = showCropIndex,
               selectedImages.indices.contains(index),
               let image = selectedImages[index] {
                FeaturePhotoCropView(image: image) { editedImage in
                    selectedImages[index] = editedImage
                }
            }
        }
        .preferredColorScheme(.light)
        .alert(
            "Generation failed",
            isPresented: Binding(
                get: { generationError != nil },
                set: { if !$0 { generationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { generationError = nil }
        } message: {
            Text(generationError ?? "Please try again.")
        }
        .onAppear {
            AppAnalytics.screen(
                "image_generation_upload",
                className: "ImageGenerationUploadView"
            )
        }
#if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-showImageDataNoticePreview") else { return }
            showDataNotice = true
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-showGeneratedImagePreview") else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            showGenerationFlow = true
        }
#endif
    }

    private func templatePreview(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            FrostedTemplatePreview(item: template)

            HStack(spacing: 10) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    if let image {
                        FrostedUploadedPhoto(image: image)
                            .frame(width: 49, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.82), lineWidth: 1))

                        if index < selectedImages.count - 1 {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 25, weight: .medium))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color(.systemGray4))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppPalette.surfaceEdge.opacity(0.88), lineWidth: 1.2)
        )
        .clipped()
    }

    private func uploadSlots(height: CGFloat) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 14
            let uploadCount = template.imageUploadCount
            let preferredItemWidth = min(151, max(118, height * 0.80))
            let stripLayout = HorizontalUploadStripLayout(
                viewportWidth: proxy.size.width,
                itemCount: uploadCount,
                preferredItemWidth: preferredItemWidth,
                spacing: spacing
            )

            if stripLayout.scrollsHorizontally {
                ScrollView(.horizontal) {
                    imageTemplateUploadSlotRow(
                        itemWidth: stripLayout.itemWidth,
                        contentWidth: stripLayout.contentWidth,
                        spacing: spacing,
                        height: height
                    )
                    .frame(minWidth: proxy.size.width, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("image-template-upload-strip")
            } else {
                imageTemplateUploadSlotRow(
                    itemWidth: stripLayout.itemWidth,
                    contentWidth: stripLayout.contentWidth,
                    spacing: spacing,
                    height: height
                )
                .frame(width: proxy.size.width, alignment: .center)
            }
        }
        .frame(height: height)
    }

    private func imageTemplateUploadSlotRow(
        itemWidth: CGFloat,
        contentWidth: CGFloat,
        spacing: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            Button {
                showPhotoSelection = true
            } label: {
                HStack(spacing: spacing) {
                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                        ImageGenerationUploadSlot(
                            image: image,
                            label: "Image\(index + 1)",
                            placeholderURL: template.uploadPlaceholderURL(at: index),
                            height: height
                        )
                        .frame(width: itemWidth)
                        .accessibilityIdentifier("image-upload-slot-\(index + 1)")
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: spacing) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    UploadPhotoEditOverlay(
                        hasImage: image != nil,
                        width: itemWidth,
                        height: height,
                        action: { showCropIndex = index }
                    )
                }
            }
        }
        .frame(width: contentWidth, height: height, alignment: .leading)
    }

    private func beginGeneration() {
        requireLogin {
            if hasAcceptedDataNotice {
                startGeneration()
            } else {
                showDataNotice = true
            }
        }
    }

    private func requireLogin(_ action: @escaping () -> Void) {
        guard isLoggedIn || ProcessInfo.processInfo.arguments.contains("-loggedIn") else {
            pendingLoginAction = action
            AppAnalytics.authGateShown(source: "image_generation")
            showLogin = true
            return
        }
        action()
    }

    private func acceptNoticeAndGenerate() {
        hasAcceptedDataNotice = true
        showDataNotice = false
        startGeneration()
    }

    private func startGeneration() {
        guard !isGenerating else { return }
        let images = selectedImages.compactMap { $0 }
        guard images.count == template.imageUploadCount else {
            AppAnalytics.generationBlocked(
                contentType: "image",
                itemID: template.id,
                reason: "missing_media"
            )
            generationError = template.imageUploadCount == 1
                ? "Please choose a source photo."
                : "Please fill all \(template.imageUploadCount) image slots."
            return
        }

        let cost = generationCost
        guard credits >= cost else {
            AppAnalytics.generationBlocked(
                contentType: "image",
                itemID: template.id,
                reason: "insufficient_credits"
            )
            showCredits = true
            return
        }
        AppAnalytics.generationStarted(
            contentType: "image",
            itemID: template.id,
            creditsCost: cost,
            inputCount: selectedImages.compactMap { $0 }.count,
            resolution: resolution
        )

        generationError = nil
        generatedImageURL = nil
        generationTaskID = nil
        pendingImageGeneration = PendingImageGenerationRequest(
            endpoint: .imageToImage,
            itemID: template.id,
            images: images,
            prompt: nil,
            options: PhotoReviveImageGenerationOptions(
                resolution: normalizedImageResolution,
                aspectRatio: imageCapabilities.normalizedAspectRatio(ratio),
                outputCount: 1
            )
        )
        isGenerating = true
        showGenerationFlow = true
    }

    private func closeGenerationFlow() {
        showGenerationFlow = false
        isGenerating = false
        pendingImageGeneration = nil
    }

    private var generationCost: Int {
        template.modelType == "text_to_image"
            ? creditPricing.textToImageCredits
            : creditPricing.imageToImageCredits
    }

    private var imageCapabilities: ImageGenerationOptionCapabilities {
        .current(forModelID: template.modelID)
    }

    private var imageSettingsSummaryValues: [String] {
        var values = [
            "\(imageCapabilities.normalizedOutputCount(outputCount)) Img",
            imageCapabilities.normalizedResolution(resolution),
        ]
        if let normalizedRatio = imageCapabilities.normalizedAspectRatio(ratio) {
            values.append(normalizedRatio)
        }
        return values
    }

    private var normalizedImageResolution: String {
        imageCapabilities.normalizedResolution(resolution)
    }

    private func applySelectedImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        var updatedImages = selectedImages
        if images.count == 1,
           let emptyIndex = updatedImages.firstIndex(where: { $0 == nil }) {
            updatedImages[emptyIndex] = images[0]
        } else {
            for (index, image) in images.prefix(updatedImages.count).enumerated() {
                updatedImages[index] = image
            }
        }
        selectedImages = updatedImages
    }
}

private struct ImageGenerationPrimaryButton: View {
    let cost: Int
    let credits: Int
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(credits >= cost ? "Generate" : "More Credits")
                        .font(.system(size: 26, weight: .heavy))
                }

                HStack(spacing: 5) {
                    Spacer()
                    Image("RewardsCreditToken")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text("\(cost)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.yellow)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 19)
            .frame(maxWidth: .infinity)
            .frame(height: 63)
            .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppPalette.ink, lineWidth: 1.2))
        }
        .buttonStyle(TemplatePressStyle())
        .disabled(isLoading)
    }
}

private struct ImageGenerationUploadSlot: View {
    let image: UIImage?
    let label: String
    let placeholderURL: URL?
    let height: CGFloat

    init(
        image: UIImage?,
        label: String,
        placeholderURL: URL? = nil,
        height: CGFloat = 188
    ) {
        self.image = image
        self.label = label
        self.placeholderURL = placeholderURL
        self.height = height
    }

    var body: some View {
        ZStack {
            if let image {
                FrostedUploadedPhoto(image: image)
            } else if let placeholderURL {
                CachedRemoteImage(url: placeholderURL) { image in
                    Image(uiImage: image).resizable().scaledToFill()
                } placeholder: {
                    uploadPlaceholder
                } failure: {
                    uploadPlaceholder
                }
            } else {
                uploadPlaceholder
            }

            if image != nil || placeholderURL != nil {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 35, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.42), radius: 3, y: 1)
            }

            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 17, weight: .regular))
                        .padding(.horizontal, 6)
                        .frame(height: 28)
                        .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 5))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(7)
            }
        }
        .frame(height: height)
        .background(
            Color(red: 1.00, green: 0.96, blue: 0.88),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(AppPalette.surfaceEdge.opacity(0.52), lineWidth: 1)
        )
        .shadow(color: AppPalette.brownInk.opacity(0.09), radius: 9, y: 4)
    }

    private var uploadPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    AppPalette.backgroundTop.opacity(0.94),
                    AppPalette.surfaceCenter.opacity(0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.68), Color.clear],
                center: .topLeading,
                startRadius: 6,
                endRadius: 150
            )

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.72))
                    Circle()
                        .stroke(Color.white.opacity(0.90), lineWidth: 1)
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(AppPalette.orange.opacity(0.86))
                }
                .frame(width: 56, height: 56)
                .shadow(color: AppPalette.brownInk.opacity(0.08), radius: 7, y: 3)

                Text("Upload Image")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.brownInk.opacity(0.86))
            }
        }
    }
}

private struct UploadPhotoEditOverlay: View {
    let hasImage: Bool
    let width: CGFloat
    let height: CGFloat
    var buttonSize: CGFloat = 31
    var padding: CGFloat = 7
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .allowsHitTesting(false)

            if hasImage {
                PhotoEditButton(
                    size: buttonSize,
                    cornerRadius: max(5, buttonSize * 0.2),
                    action: action
                )
                .padding(padding)
            }
        }
        .frame(width: width, height: height)
    }
}

private struct PhotoEditButton: View {
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 8
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "crop")
                .font(.system(size: max(17, size * 0.5), weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit uploaded photo")
        .accessibilityIdentifier("edit-uploaded-photo")
    }
}

private struct TemplateFirstFrameView: View {
    let item: TemplateItem

    var body: some View {
        Group {
            if !item.imageName.isEmpty {
                Image(item.imageName)
                    .resizable()
                    .scaledToFill()
            } else if let coverImageURL = item.coverImageURL {
                CachedRemoteImage(url: coverImageURL) { image in
                    Image(uiImage: image).resizable().scaledToFill()
                } placeholder: {
                    Color(.systemGray4)
                } failure: {
                    Color(.systemGray4)
                }
            } else {
                TemplateMediaView(item: item, gravity: .resizeAspectFill)
            }
        }
        .clipped()
    }
}

private struct ImageAIDataProcessingNotice: View {
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let cardHeight = min(max(proxy.size.height - 44, 420), 700)

            ZStack {
                Color.black.opacity(0.68)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    noticeHeader

                    ScrollView {
                        noticeCopy
                            .padding(.horizontal, 24)
                            .padding(.vertical, 18)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)

                    Divider()
                        .overlay(AppPalette.surfaceEdge.opacity(0.22))

                    noticeActions
                }
                .frame(maxWidth: 380)
                .frame(height: cardHeight)
                .background(
                    Color(red: 1.0, green: 0.97, blue: 0.89),
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(AppPalette.surfaceEdge.opacity(0.88), lineWidth: 1.4)
                )
                .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
                .padding(.horizontal, 24)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("image-ai-data-notice")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var noticeHeader: some View {
        VStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.88, blue: 0.62))

                Circle()
                    .stroke(.white.opacity(0.92), lineWidth: 2)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(AppPalette.orange)
            }
            .frame(width: 64, height: 64)
            .shadow(color: AppPalette.brownInk.opacity(0.13), radius: 6, y: 3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Data privacy")
            .accessibilityIdentifier("image-ai-data-notice-icon")

            Text("AI Data Processing Notice")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(AppPalette.brownInk)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private var noticeCopy: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("To generate images, your selected photos and input data will be sent to our servers and may be processed by third-party AI service providers.")

            VStack(alignment: .leading, spacing: 9) {
                noticeSectionTitle("Data shared includes")
                noticeBullet("Selected photos")
                noticeBullet("Generation parameters, such as prompts and styles")
            }

            VStack(alignment: .leading, spacing: 7) {
                noticeSectionTitle("Purpose")
                Text("Your data is used only to generate the requested content and is not used for training or unrelated purposes.")
            }

            Text("By tapping “Agree and Continue”, you agree to this data processing and sharing.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppPalette.brownInk.opacity(0.74))
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(AppPalette.brownInk)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func noticeSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(AppPalette.brownInk)
    }

    private func noticeBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(AppPalette.orange)
                .frame(width: 6, height: 6)
                .padding(.top, 7)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noticeActions: some View {
        VStack(spacing: 4) {
            Button(action: onAgree) {
                Text("Agree and Continue")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppPalette.orange, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("image-ai-data-notice-agree")

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppPalette.surfaceEdge)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("image-ai-data-notice-cancel")
        }
        .padding(.horizontal, 20)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }
}

private enum ImageGenerationStage: Equatable {
    case loading
    case result
    case detail
    case saved
    case failed(String)
}

private struct ImageGenerationFlowView: View {
    let title: String
    let template: TemplateItem
    let generatedImageURL: URL?
    let taskID: String?
    var loadingPreviewImage: UIImage? = nil
    var submissionAction: (@MainActor () async throws -> PhotoReviveImageGenerationSubmission)? = nil
    var onSubmission: ((PhotoReviveImageGenerationSubmission) -> Void)? = nil
    var recommendationItems: [TemplateItem] = []
    var photoToVideoGenerationTarget: FeatureGenerationTarget? = nil
    @Binding var credits: Int
    let onRegenerate: () -> Void
    let onClose: () -> Void

    @State private var stage = ImageGenerationStage.loading
    @State private var selectedTab = AppTab.me
    @State private var showPaywall = false
    @State private var showVideoGenerator = false
    @State private var showSettings = false
    @State private var selectedRecommendation: TemplateItem?
    @State private var generatedImage: UIImage?
    @State private var isExporting = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var exportError: String?
    @State private var resolvedGeneratedImageURL: URL?
    @State private var submittedTaskID: String?
    @State private var hasStartedBackgroundWork = false
    @State private var progressRecordID: UUID?
    @State private var permitsAutomaticHistoryNavigation = true
    @AppStorage("isSubscribed") private var isSubscribed = false

    var body: some View {
        ZStack {
            if stage == .detail {
                detailContent
            } else {
                PaperTextureBackground()

                switch stage {
                case .loading, .result:
                    workspaceContent
                case .saved:
                    savedContent
                case .failed(let message):
                    failedContent(message: message)
                case .detail:
                    EmptyView()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if stage != .detail && stage != .saved {
                BottomTabBar(selection: $selectedTab, onSelect: navigateToMainTab)
            }
        }
        .onAppear {
            startBackgroundWorkIfNeeded()
        }
        .task(id: resolvedGeneratedImageURL) {
            guard let resolvedGeneratedImageURL else { return }
            if let (data, _) = try? await URLSession.shared.data(from: resolvedGeneratedImageURL) {
                generatedImage = UIImage(data: data)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallOfferFlowView(analyticsSource: "image_remove_watermark")
        }
        .fullScreenCover(isPresented: $showVideoGenerator) {
            FixedVideoGeneratorFeature(
                initialMode: .image,
                credits: $credits,
                initialImage: generatedImage,
                imageGenerationTarget: photoToVideoGenerationTarget
            )
        }
        .fullScreenCover(item: $selectedRecommendation) { item in
            ImageGenerationUploadView(
                template: item,
                credits: $credits,
                recommendationItems: recommendationItems.filter { $0.id != item.id },
                photoToVideoGenerationTarget: photoToVideoGenerationTarget
            )
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(credits: $credits)
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                GeneratedMediaActivityView(activityItems: [shareURL])
            }
        }
        .alert(
            "Export unavailable",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Please try again.")
        }
        .preferredColorScheme(stage == .detail ? .dark : .light)
        .onAppear {
            AppAnalytics.screen(
                "image_generation_progress",
                className: "ImageGenerationFlowView"
            )
        }
    }

    @MainActor
    private func startBackgroundWorkIfNeeded() {
        guard stage == .loading, !hasStartedBackgroundWork else { return }
        hasStartedBackgroundWork = true
        let shouldTrackProgress: Bool
#if DEBUG
        shouldTrackProgress = submissionAction != nil
            || taskID != nil
            || ProcessInfo.processInfo.arguments.contains("-holdGeneratedImageLoading")
#else
        shouldTrackProgress = submissionAction != nil || taskID != nil
#endif
        if shouldTrackProgress {
            progressRecordID = BackgroundGenerationWorkStore.shared.register(
                kind: .image,
                title: title,
                subtitle: template.title,
                previewImage: loadingPreviewImage,
                serverTaskID: taskID
            )
        }
        let recordID = progressRecordID
        BackgroundGenerationWorkStore.shared.start {
            await runLoadingFlow(progressRecordID: recordID)
        }
    }

    private func navigateToMainTab(_ tab: AppTab) {
        permitsAutomaticHistoryNavigation = false
        completeNavigation(
            to: tab,
            historyKind: tab == .me ? .photo : nil
        )
    }

    private func navigateToCompletedImageHistory() {
        guard permitsAutomaticHistoryNavigation else { return }
        completeNavigation(to: .me, historyKind: .photo)
    }

    private func completeNavigation(
        to tab: AppTab,
        historyKind: MeHistoryKind? = nil
    ) {
        selectedTab = tab
        onClose()
        let historyKindRawValue = historyKind?.rawValue
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .appTabNavigationRequested,
                object: tab,
                userInfo: historyKindRawValue.map {
                    [Notification.Name.appTabNavigationHistoryKindKey: $0]
                }
            )
        }
    }

    @MainActor
    private func runLoadingFlow(progressRecordID: UUID?) async {
        if let submissionAction {
            let generationStartedAt = Date()
            do {
                // Give the full-screen loading page a frame to present before
                // large source images are encoded and uploaded.
                try await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, stage == .loading else { return }
                let submission = try await submissionAction()
                guard !Task.isCancelled, stage == .loading else { return }
                guard let resultURL = submission.resultURL else {
                    throw PhotoReviveAPIError.invalidResponse
                }

                resolvedGeneratedImageURL = resultURL
                submittedTaskID = submission.taskID
                BackgroundGenerationWorkStore.shared.markSubmitted(
                    recordID: progressRecordID,
                    serverTaskID: submission.taskID
                )
                BackgroundGenerationWorkStore.shared.markCompleted(
                    recordID: progressRecordID,
                    resultURL: resultURL
                )
                onSubmission?(submission)
                AppAnalytics.generationSubmitted(
                    contentType: "image",
                    itemID: template.id
                )
                AppAnalytics.generationCompleted(
                    contentType: "image",
                    itemID: template.id,
                    elapsedMilliseconds: Int(
                        Date().timeIntervalSince(generationStartedAt) * 1_000
                    )
                )
                await AppAccountStore.shared.refreshHistory()
                BackgroundGenerationWorkStore.shared.reconcile(
                    with: AppAccountStore.shared.historyTasks
                )
                navigateToCompletedImageHistory()
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.userFacingEnglishMessage(
                    fallback: "Image generation failed. Please try again."
                )
                BackgroundGenerationWorkStore.shared.markFailed(
                    recordID: progressRecordID,
                    message: message
                )
                AppAnalytics.generationFailed(
                    contentType: "image",
                    itemID: template.id,
                    stage: "submission",
                    failureType: AppAnalytics.apiFailureType(error)
                )
                stage = .failed(message)
            }
            return
        }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showGeneratedImagePreview") {
            let previewDelay = ProcessInfo.processInfo.arguments.contains("-holdGeneratedImageLoading")
                ? 30_000
                : 2_400
            try? await Task.sleep(for: .milliseconds(previewDelay))
            guard !Task.isCancelled, stage == .loading else { return }
            await AppAccountStore.shared.refreshHistory()
            navigateToCompletedImageHistory()
            return
        }
#endif
        if let generatedImageURL {
            resolvedGeneratedImageURL = generatedImageURL
            submittedTaskID = taskID
            BackgroundGenerationWorkStore.shared.markCompleted(
                recordID: progressRecordID,
                resultURL: generatedImageURL
            )
            await AppAccountStore.shared.refreshHistory()
            BackgroundGenerationWorkStore.shared.reconcile(
                with: AppAccountStore.shared.historyTasks
            )
            navigateToCompletedImageHistory()
        } else {
            let message = "The generated image is not available. Please try again."
            BackgroundGenerationWorkStore.shared.markFailed(
                recordID: progressRecordID,
                message: message
            )
            stage = .failed(message)
        }
    }

    private var workspaceContent: some View {
        VStack(spacing: 0) {
            imageWorkspaceHeader

            VStack(alignment: .leading, spacing: 10) {
                Text("Today")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppPalette.ink)

                Button {
                    guard stage == .result else { return }
                    stage = .detail
                } label: {
                    ZStack {
                        generatedImageView(contentMode: .fill)

                        if stage == .loading {
                            Color.black.opacity(0.50)
                            VStack(spacing: 18) {
                                VideoGenerationDots()
                                Text("Please wait\n(1-3 min)")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.32))
                                    .multilineTextAlignment(.center)
                            }
                        } else {
                            GeneratedContentWatermark()
                        }
                    }
                    .frame(width: 115, height: 174)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(stage == .loading)
                .accessibilityIdentifier("generated-image-card")
                .accessibilityLabel(stage == .loading ? "Generating image" : "Generated image")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 29)

            Text("You are responsible for your rendered content. Use our app\nlegally and ethically. Our policies apply.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppPalette.brownInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 38)

            Spacer(minLength: 0)
        }
        .accessibilityIdentifier(stage == .loading ? "image-generation-loading" : "image-generation-result")
    }

    private func failedContent(message: String) -> some View {
        VStack(spacing: 0) {
            imageWorkspaceHeader

            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(AppPalette.accent)

                Text("Generation failed")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(AppPalette.ink)

                Text(message)
                    .font(.system(size: 16))
                    .foregroundStyle(AppPalette.brownInk)
                    .multilineTextAlignment(.center)

                Button(action: onRegenerate) {
                    Text("Try Again")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppPalette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("image-generation-try-again")
            }
            .padding(.horizontal, 30)
            .padding(.top, 88)

            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("image-generation-failed")
    }

    private var imageWorkspaceHeader: some View {
        HStack {
            HStack(spacing: 0) {
                Button {
                    navigateToMainTab(.video)
                } label: {
                    Text("Video")
                        .foregroundStyle(AppPalette.ink)
                        .frame(width: 72, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Browse AI Video")

                Button {
                    navigateToMainTab(.photo)
                } label: {
                    Text("Photo")
                        .foregroundStyle(AppPalette.accent.opacity(0.84))
                        .frame(width: 72, height: 40)
                        .background(Color.white.opacity(0.45), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Browse AI Photo")
            }
            .font(.system(size: 18, weight: .bold))
            .padding(2)
            .background(Color.white.opacity(0.20), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.68), lineWidth: 1))

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.48), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Generation settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var detailContent: some View {
        ZStack {
            Color(red: 0.16, green: 0.16, blue: 0.16)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { stage = .result } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 25, weight: .light))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(.white.opacity(0.08), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if !isSubscribed {
                        Button { showPaywall = true } label: {
                            Label("No Watermark", systemImage: "eraser")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.48))
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .background(.black.opacity(0.46), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                generatedImageView(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 557)
                    .overlay { GeneratedContentWatermark() }
                    .clipped()
                    .padding(.horizontal, 48)
                    .padding(.top, 17)

                HStack(spacing: 14) {
                    Button {
                        onRegenerate()
                    } label: {
                        Label("Recreate", systemImage: "arrow.clockwise")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.white, in: Capsule())
                    }

                    Button {
                        saveImage()
                    } label: {
                        Label("Save", systemImage: "arrow.down.to.line")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(AppPalette.accent, in: Capsule())
                    }
                    .disabled(isExporting)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 19)
            }
        }
        .accessibilityIdentifier("generated-image-detail")
    }

    private var savedContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    Text("Saved")
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundStyle(AppPalette.ink)

                    HStack {
                        Button { stage = .detail } label: {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(AppPalette.ink)
                                .frame(width: 54, height: 54)
                                .background(.white.opacity(0.48), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: onClose) {
                            Image(systemName: "house")
                                .font(.system(size: 23, weight: .medium))
                                .foregroundStyle(AppPalette.ink)
                                .frame(width: 54, height: 54)
                                .background(.white.opacity(0.48), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                generatedImageView(contentMode: .fit)
                    .frame(width: 212, height: 378)
                    .background(.white)
                    .overlay { GeneratedContentWatermark() }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, 12)

                if !isSubscribed {
                    Button { showPaywall = true } label: {
                        Text("Remove Watermark")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.54))
                            .padding(.horizontal, 24)
                            .frame(height: 44)
                            .background(AppPalette.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .offset(y: -22)
                    .padding(.bottom, -10)
                }

                if photoToVideoGenerationTarget != nil {
                    Button { showVideoGenerator = true } label: {
                        Label("Photo To Video", systemImage: "photo.badge.arrow.down")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.82, blue: 0.46), Color(red: 0.78, green: 0.50, blue: 0.23)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("image-to-video-button")
                }

                Button(action: shareImage) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.72), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
                .accessibilityLabel("Share generated photo")
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Text("What's next? Try these:")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(AppPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(recommendationItems) { item in
                            ImageGenerationSuggestion(item: item) {
                                selectedRecommendation = item
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("saved-image-result")
    }

    @ViewBuilder
    private func generatedImageView(contentMode: ContentMode) -> some View {
        if let resolvedGeneratedImageURL {
            CachedRemoteImage(url: resolvedGeneratedImageURL) { image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } placeholder: {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView()
                }
            } failure: {
                ZStack {
                    Color.black.opacity(0.08)
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(AppPalette.surfaceEdge)
                }
            }
        } else if let loadingPreviewImage {
            Image(uiImage: loadingPreviewImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            ZStack {
                Color.black.opacity(0.08)
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(AppPalette.surfaceEdge)
            }
        }
    }

    private func saveImage() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let image = try await exportImage()
                let fileURL = try GeneratedMediaExporter.prepareImage(
                    image,
                    addsWatermark: !isSubscribed
                )
                try await GeneratedMediaExporter.saveImage(at: fileURL)
                AppAnalytics.contentSaved(contentType: "image", itemID: template.id)
                stage = .saved
            } catch {
                exportError = error.userFacingEnglishMessage(
                    fallback: "The image could not be saved. Please try again."
                )
            }
        }
    }

    private func shareImage() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let image = try await exportImage()
                shareURL = try GeneratedMediaExporter.prepareImage(
                    image,
                    addsWatermark: !isSubscribed
                )
                showShareSheet = true
            } catch {
                exportError = error.userFacingEnglishMessage(
                    fallback: "The image could not be shared. Please try again."
                )
            }
        }
    }

    private func exportImage() async throws -> UIImage {
        if let generatedImage { return generatedImage }
        guard let resolvedGeneratedImageURL else {
            throw GeneratedMediaExportError.mediaUnavailable
        }
        let (data, response) = try await URLSession.shared.data(from: resolvedGeneratedImageURL)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let image = UIImage(data: data) else {
            throw GeneratedMediaExportError.mediaUnavailable
        }
        generatedImage = image
        return image
    }
}

private struct ImageGenerationSuggestion: View {
    let item: TemplateItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                TemplateMediaView(item: item, gravity: .resizeAspectFill)
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(8)
            }
            .frame(width: 86, height: 130)
            .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Try \(item.title)")
    }
}

private struct FixedAIImageFeature: View {
    let creditPricing: AppCreditPricing
    let recommendationItems: [TemplateItem]
    let photoToVideoGenerationTarget: FeatureGenerationTarget?
    let imageGenerationTarget: FeatureGenerationTarget?
    let textGenerationTarget: FeatureGenerationTarget?
    @Binding var credits: Int
    @Environment(\.dismiss) private var dismiss
    @State private var mode: AIImageMode
    @State private var selectedImages: [UIImage] = []
    @State private var showPhotoSelection = false
    @State private var prompt = ""
    @State private var promptInsertionRequest: PromptEditorInsertionRequest?
    @State private var showSettings = false
    @State private var showCredits = false
    @State private var showCropIndex: Int?
    @State private var resolution = PhotoReviveImageGenerationOptions.providerDefaultResolution
    @State private var ratio = "9:16"
    @State private var outputCount = "1"
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generatedImageURL: URL?
    @State private var generationTaskID: String?
    @State private var showGenerationFlow = false
    @State private var pendingImageGeneration: PendingImageGenerationRequest?

    init(
        creditPricing: AppCreditPricing = .defaultValue,
        credits: Binding<Int>,
        initialMode: AIImageMode = .image,
        recommendationItems: [TemplateItem] = [],
        photoToVideoGenerationTarget: FeatureGenerationTarget? = nil,
        imageGenerationTarget: FeatureGenerationTarget? = nil,
        textGenerationTarget: FeatureGenerationTarget? = nil
    ) {
        self.creditPricing = creditPricing
        self.recommendationItems = recommendationItems
        self.photoToVideoGenerationTarget = photoToVideoGenerationTarget
        self.imageGenerationTarget = imageGenerationTarget
        self.textGenerationTarget = textGenerationTarget
        _credits = credits
        let resolvedMode: AIImageMode
        if initialMode == .image,
           imageGenerationTarget == nil,
           textGenerationTarget != nil {
            resolvedMode = .text
        } else if initialMode == .text,
                  textGenerationTarget == nil,
                  imageGenerationTarget != nil {
            resolvedMode = .image
        } else {
            resolvedMode = initialMode
        }
        _mode = State(initialValue: resolvedMode)
    }

    var body: some View {
        ZStack {
            FixedFeatureScaffold(
                title: "AI Image",
                showsHelp: false,
                onBack: { dismiss() }
            ) { contentSize in
                let showsTabs = imageGenerationTarget != nil && textGenerationTarget != nil
                let layout = FixedAIImageUploadLayout(
                    viewportSize: contentSize,
                    showsTabs: showsTabs,
                    includesUploads: mode == .image
                )

                VStack(alignment: .leading, spacing: layout.spacing) {
                    if showsTabs {
                        FeatureModeTabs(
                            options: [("Image to Image", .image), ("Text to Image", .text)],
                            selection: $mode
                        )
                        .frame(height: layout.tabsHeight)
                    }

                    if mode == .image {
                        Text("Image(\(selectedImages.count)/3)")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(AppPalette.brownInk)
                            .frame(height: layout.titleHeight, alignment: .leading)

                        GeometryReader { slotProxy in
                            let slotSpacing: CGFloat = 14
                            let preferredItemWidth = min(
                                158,
                                max(118, layout.uploadHeight * 0.72)
                            )
                            let stripLayout = HorizontalUploadStripLayout(
                                viewportWidth: slotProxy.size.width,
                                itemCount: 3,
                                preferredItemWidth: preferredItemWidth,
                                spacing: slotSpacing
                            )

                            ScrollView(.horizontal) {
                                fixedAIImageUploadSlotRow(
                                    itemWidth: stripLayout.itemWidth,
                                    contentWidth: stripLayout.contentWidth,
                                    spacing: slotSpacing,
                                    height: layout.uploadHeight
                                )
                                .frame(minWidth: slotProxy.size.width, alignment: .leading)
                            }
                            .scrollIndicators(.hidden)
                            .scrollBounceBehavior(.basedOnSize)
                            .accessibilityIdentifier("fixed-ai-image-upload-strip")
                        }
                        .frame(height: layout.uploadHeight)
                    }

                    ZStack(alignment: .bottom) {
                        FeaturePromptBox(
                            text: $prompt,
                            placeholder: mode == .image ? "Describe the content you want to create." : "Describe the image you want to create.Example: A puppy running on the grass.",
                            height: layout.promptHeight,
                            insertionRequest: promptInsertionRequest
                        )

                        if mode == .image {
                            HStack {
                                imageReferenceButton
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 9)
                            .zIndex(2)
                        }
                    }

                    FeatureSettingsSummary(values: imageSettingsSummaryValues, onTap: { showSettings = true })
                        .frame(height: layout.settingsHeight)
                }
                .frame(height: contentSize.height, alignment: .top)
            } footer: {
                FeaturePrimaryButton(
                    title: isGenerating ? "Generating…" : "Generate",
                    cost: mode == .image
                        ? creditPricing.imageToImageCredits
                        : creditPricing.textToImageCredits,
                    credits: $credits,
                    onNeedCredits: { showCredits = true },
                    onCreate: startGeneration
                )
                .disabled(isGenerating)
            }

        }
        .sheet(isPresented: $showPhotoSelection) {
            PhotoSelectionSheet(maximumSelectionCount: 3) { images in
                applySelectedImages(images)
            }
            .presentationDetents([.fraction(0.73), .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(30)
        }
        .sheet(isPresented: $showSettings) {
            AIImageOutputSettingsSheet(
                imageCapabilities: imageCapabilities,
                resolution: $resolution,
                ratio: $ratio,
                outputCount: $outputCount
            )
            .presentationDetents([.fraction(0.64)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(30)
        }
        .fullScreenCover(isPresented: $showCredits) { CreditCenterView(credits: $credits) }
        .fullScreenCover(isPresented: $showGenerationFlow) {
            if let pendingImageGeneration {
                ImageGenerationFlowView(
                    title: "AI Image",
                    template: resultTemplate,
                    generatedImageURL: generatedImageURL,
                    taskID: generationTaskID,
                    loadingPreviewImage: selectedImages.first,
                    submissionAction: {
                        try await pendingImageGeneration.submit()
                    },
                    onSubmission: { submission in
                        credits = submission.creditsBalance
                        generatedImageURL = submission.resultURL
                        generationTaskID = submission.taskID
                        isGenerating = false
                    },
                    recommendationItems: recommendationItems,
                    photoToVideoGenerationTarget: photoToVideoGenerationTarget,
                    credits: $credits,
                    onRegenerate: closeGenerationFlow,
                    onClose: {
                        closeGenerationFlow()
                        dismiss()
                    }
                )
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { showCropIndex != nil },
                set: { if !$0 { showCropIndex = nil } }
            )
        ) {
            if let index = showCropIndex, selectedImages.indices.contains(index) {
                FeaturePhotoCropView(image: selectedImages[index]) { editedImage in
                    selectedImages[index] = editedImage
                }
            }
        }
        .preferredColorScheme(.light)
        .alert(
            "Generation unavailable",
            isPresented: Binding(
                get: { generationError != nil },
                set: { if !$0 { generationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { generationError = nil }
        } message: {
            Text(generationError ?? "Please try again.")
        }
        .onChange(of: mode) { _, _ in
            normalizeImageSelections()
        }
    }

    private func fixedAIImageUploadSlotRow(
        itemWidth: CGFloat,
        contentWidth: CGFloat,
        spacing: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            Button {
                showPhotoSelection = true
            } label: {
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { index in
                        FeatureImageSlot(
                            image: selectedImages.indices.contains(index) ? selectedImages[index] : nil,
                            title: index == 0 ? nil : "Optional",
                            width: itemWidth,
                            height: height
                        )
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { index in
                    UploadPhotoEditOverlay(
                        hasImage: selectedImages.indices.contains(index),
                        width: itemWidth,
                        height: height,
                        buttonSize: 34,
                        padding: 8,
                        action: { showCropIndex = index }
                    )
                }
            }
        }
        .frame(width: contentWidth, height: height, alignment: .leading)
    }

    @ViewBuilder
    private var imageReferenceButton: some View {
        if selectedImages.isEmpty {
            Button {
                requestPromptInsertion("@")
            } label: {
                imageReferenceButtonLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Insert at sign")
        } else {
            Menu {
                ForEach(selectedImages.indices, id: \.self) { index in
                    Button("@Image\(index + 1)") {
                        requestPromptInsertion("@Image\(index + 1)")
                    }
                }
            } label: {
                imageReferenceButtonLabel
            }
            .menuStyle(.button)
            .accessibilityLabel("Mention an uploaded image")
        }
    }

    private var imageReferenceButtonLabel: some View {
        Text("@")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(AppPalette.surfaceEdge)
            .frame(width: 42, height: 42)
            .background(Color.white.opacity(0.40), in: RoundedRectangle(cornerRadius: 10))
    }

    private func requestPromptInsertion(_ text: String) {
        promptInsertionRequest = PromptEditorInsertionRequest(text: text)
    }

    private func applySelectedImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        if images.count == 1, selectedImages.count < 3 {
            selectedImages.append(images[0])
        } else {
            selectedImages = Array(images.prefix(3))
        }
    }

    private var activeGenerationTarget: FeatureGenerationTarget? {
        mode == .image ? imageGenerationTarget : textGenerationTarget
    }

    private var resultTemplate: TemplateItem {
        TemplateItem(
            id: activeGenerationTarget?.itemID ?? "unconfigured-ai-image",
            title: "AI Image",
            generationKind: .image,
            estimatedCredits: mode == .image
                ? creditPricing.imageToImageCredits
                : creditPricing.textToImageCredits,
            modelType: activeGenerationTarget?.modelType,
            modelID: activeGenerationTarget?.modelID
        )
    }

    private func startGeneration() {
        guard !isGenerating else { return }
        guard let target = activeGenerationTarget else {
            generationError = "This feature has not been connected to a CMS generation template yet."
            return
        }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .image && selectedImages.isEmpty {
            generationError = "Please choose at least one source photo."
            return
        }
        if mode == .text && trimmedPrompt.isEmpty && target.promptTemplate == nil {
            generationError = "Please describe the image you want to create."
            return
        }

        let endpoint: PendingImageGenerationEndpoint
        if mode == .image && target.endpoint == "image-to-image" {
            endpoint = .imageToImage
        } else if mode == .text && target.endpoint == "text-to-image" {
            endpoint = .textToImage
        } else {
            generationError = "The CMS generation target for this feature is invalid."
            return
        }

        generationError = nil
        generatedImageURL = nil
        generationTaskID = nil
        pendingImageGeneration = PendingImageGenerationRequest(
            endpoint: endpoint,
            itemID: target.itemID,
            images: selectedImages,
            prompt: trimmedPrompt.isEmpty ? nil : trimmedPrompt,
            options: PhotoReviveImageGenerationOptions(
                resolution: normalizedImageResolution,
                aspectRatio: imageCapabilities.normalizedAspectRatio(ratio),
                outputCount: 1
            )
        )
        isGenerating = true
        showGenerationFlow = true
    }

    private func closeGenerationFlow() {
        showGenerationFlow = false
        isGenerating = false
        pendingImageGeneration = nil
    }

    private var normalizedImageResolution: String {
        imageCapabilities.normalizedResolution(resolution)
    }

    private var imageCapabilities: ImageGenerationOptionCapabilities {
        .current(forModelID: activeGenerationTarget?.modelID)
    }

    private var imageSettingsSummaryValues: [String] {
        var values = [
            "\(imageCapabilities.normalizedOutputCount(outputCount)) Img",
            imageCapabilities.normalizedResolution(resolution),
        ]
        if let normalizedRatio = imageCapabilities.normalizedAspectRatio(ratio) {
            values.append(normalizedRatio)
        }
        return values
    }

    private func normalizeImageSelections() {
        resolution = imageCapabilities.normalizedResolution(resolution)
        outputCount = imageCapabilities.normalizedOutputCount(outputCount)
        if let normalizedRatio = imageCapabilities.normalizedAspectRatio(ratio) {
            ratio = normalizedRatio
        }
    }
}

private enum AIImageMode: Hashable {
    case image
    case text
}

private struct FeatureAddPhotoIcon: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "photo")
                .font(.system(size: 25, weight: .medium))
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .offset(x: 5, y: -5)
        }
    }
}

private struct FeatureImageSlot: View {
    let image: UIImage?
    let title: String?
    var width: CGFloat = 158
    var height: CGFloat = 218

    var body: some View {
        ZStack {
            if let image {
                FrostedUploadedPhoto(image: image)
            } else {
                VStack(spacing: 10) {
                    FeatureAddPhotoIcon()
                        .frame(width: 34, height: 34)
                    if let title {
                        Text(title)
                            .font(.system(size: 18, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .foregroundStyle(AppPalette.surfaceEdge)
            }
        }
        .frame(width: width, height: height)
        .background(Color.white.opacity(0.40), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppPalette.surfaceEdge.opacity(0.75), lineWidth: 1.2))
    }
}

private struct AIImageOutputSettingsSheet: View {
    let imageCapabilities: ImageGenerationOptionCapabilities
    @Binding var resolution: String
    @Binding var ratio: String
    @Binding var outputCount: String
    @Environment(\.dismiss) private var dismiss

    private let selectionColor = Color(red: 0.86, green: 0.30, blue: 0.22)
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingSection("Resolution") {
                    singleChoiceGrid(
                        imageCapabilities.resolutions,
                        selection: $resolution
                    )
                }

                if !imageCapabilities.aspectRatios.isEmpty {
                    settingSection("Ratio") {
                        singleChoiceGrid(
                            imageCapabilities.aspectRatios,
                            selection: $ratio
                        )
                    }
                }

                settingSection("Output Image Number") {
                    singleChoiceGrid(
                        imageCapabilities.outputCounts,
                        selection: $outputCount
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 63)
            .padding(.bottom, 18)
        }
        .background(.white)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .padding(.top, 27)
            .padding(.trailing, 5)
            .accessibilityLabel("Close output settings")
        }
        .onAppear(perform: normalizeSelections)
    }

    private func settingSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.14))
            content()
        }
    }

    private func singleChoiceGrid(_ values: [String], selection: Binding<String>) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(values, id: \.self) { value in
                singleChoice(value, selection: selection)
            }
        }
    }

    private func normalizeSelections() {
        resolution = imageCapabilities.normalizedResolution(resolution)
        outputCount = imageCapabilities.normalizedOutputCount(outputCount)
        if let normalizedRatio = imageCapabilities.normalizedAspectRatio(ratio) {
            ratio = normalizedRatio
        }
    }

    private func singleChoice(_ value: String, selection: Binding<String>) -> some View {
        Button { selection.wrappedValue = value } label: {
            Text(value)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(selection.wrappedValue == value ? selectionColor : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(selection.wrappedValue == value ? .white : Color(red: 0.95, green: 0.95, blue: 0.95), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(selection.wrappedValue == value ? selectionColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct FeatureSettingsSheet: View {
    enum Mode: Equatable { case video, image }

    let mode: Mode
    let videoCapabilities: VideoGenerationOptionCapabilities
    let imageCapabilities: ImageGenerationOptionCapabilities
    @Binding var soundEnabled: Bool
    @Binding var multiShotEnabled: Bool
    @Binding var duration: String
    @Binding var resolution: String
    @Binding var ratio: String
    @Binding var outputCount: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mode == .video {
                        if videoCapabilities.supportsSound {
                            settingToggle("Sounds", off: "speaker.slash.fill", on: "speaker.wave.2.fill", value: $soundEnabled)
                        }
                        if videoCapabilities.supportsMultiShot {
                            settingToggle("Multi-Shot Video", off: "video.slash.fill", on: "video.badge.waveform.fill", value: $multiShotEnabled)
                        }
                        settingGrid("Duration", values: videoCapabilities.durations, selection: $duration)
                        settingGrid("Resolution", values: videoCapabilities.resolutions, selection: $resolution)
                        settingGrid("Ratio", values: videoCapabilities.aspectRatios, selection: $ratio)
                    } else {
                        settingGrid(
                            "Resolution",
                            values: imageCapabilities.resolutions,
                            selection: $resolution
                        )
                        if !imageCapabilities.aspectRatios.isEmpty {
                            settingGrid("Ratio", values: imageCapabilities.aspectRatios, selection: $ratio)
                        }
                        settingGrid(
                            "Output Image Number",
                            values: imageCapabilities.outputCounts,
                            selection: $outputCount
                        )
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Output Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                }
            }
        }
        .tint(AppPalette.accent)
        .onAppear(perform: normalizeSelections)
    }

    private func normalizeSelections() {
        if mode == .image {
            resolution = imageCapabilities.normalizedResolution(resolution)
            outputCount = imageCapabilities.normalizedOutputCount(outputCount)
            if let normalizedRatio = imageCapabilities.normalizedAspectRatio(ratio) {
                ratio = normalizedRatio
            }
            return
        }
        duration = videoCapabilities.normalizedDuration(duration)
        resolution = videoCapabilities.normalizedResolution(resolution)
        ratio = videoCapabilities.normalizedAspectRatio(ratio)
        if !videoCapabilities.supportsSound { soundEnabled = false }
        if !videoCapabilities.supportsMultiShot { multiShotEnabled = false }
    }

    private func settingToggle(_ title: String, off: String, on: String, value: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3)
            HStack(spacing: 14) {
                settingIcon(off, selected: !value.wrappedValue) { value.wrappedValue = false }
                settingIcon(on, selected: value.wrappedValue) { value.wrappedValue = true }
            }
        }
    }

    private func settingIcon(_ icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(selected ? AppPalette.accent : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? AppPalette.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func settingGrid(_ title: String, values: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection.wrappedValue = value
                    } label: {
                        Text(value)
                            .font(.body.weight(.medium))
                            .foregroundStyle(selection.wrappedValue == value ? AppPalette.accent : .primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection.wrappedValue == value ? AppPalette.accent : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct FeaturePhotoCropView: View {
    @Environment(\.dismiss) private var dismiss
    private let originalImage: UIImage
    private let onSave: (UIImage) -> Void

    @State private var workingImage: UIImage
    @State private var selectedAspect = PhotoCropAspect.freeform
    @State private var freeformAspect: CGFloat
    @State private var settledZoom: CGFloat = 1
    @State private var settledOffset: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var resizeStartAspect: CGFloat?
    @GestureState private var gestureZoom: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero

    init(image: UIImage, onSave: @escaping (UIImage) -> Void = { _ in }) {
        let normalizedImage = PhotoCropRenderer.normalized(image)
        originalImage = normalizedImage
        self.onSave = onSave
        _workingImage = State(initialValue: normalizedImage)
        _freeformAspect = State(
            initialValue: normalizedImage.size.height > 0
                ? normalizedImage.size.width / normalizedImage.size.height
                : 1
        )
    }

    var body: some View {
        GeometryReader { proxy in
            Color(red: 0.06, green: 0.06, blue: 0.06).ignoresSafeArea()

            VStack(spacing: 0) {
                cropWorkspace(
                    size: CGSize(
                        width: max(1, proxy.size.width - 28),
                        height: max(240, min(proxy.size.height * 0.60, proxy.size.height - 260))
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: max(240, min(proxy.size.height * 0.60, proxy.size.height - 260)))
                .padding(.top, 18)

                HStack(spacing: 27) {
                    cropToolButton("rotate.right", label: "Rotate photo") {
                        workingImage = PhotoCropRenderer.rotatedClockwise(workingImage)
                        resetViewport()
                    }

                    cropToolButton("triangle.lefthalf.filled", label: "Flip photo") {
                        workingImage = PhotoCropRenderer.flippedHorizontally(workingImage)
                        resetViewport()
                    }

                    Spacer()

                    cropToolButton("arrow.counterclockwise", label: "Reset photo edits") {
                        workingImage = originalImage
                        freeformAspect = originalAspect
                        selectedAspect = .freeform
                        resetViewport()
                    }
                }
                .padding(.horizontal, 44)
                .padding(.top, 22)

                ScrollView(.horizontal) {
                    HStack(spacing: 18) {
                        ForEach(PhotoCropAspect.allCases) { aspect in
                            Button {
                                selectedAspect = aspect
                                resetViewport()
                            } label: {
                                Text(aspect.displayTitle)
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(selectedAspect == aspect ? .white : .gray)
                                    .padding(.horizontal, selectedAspect == aspect ? 16 : 0)
                                    .frame(height: 44)
                                    .background(
                                        selectedAspect == aspect ? Color.gray.opacity(0.75) : .clear,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Crop ratio \(aspect.rawValue)")
                            .accessibilityAddTraits(selectedAspect == aspect ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 34)
                }
                .scrollIndicators(.hidden)
                .padding(.top, 16)

                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: applyEdits) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 104, height: 58)
                            .background(AppPalette.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Apply photo edits")
                    .accessibilityIdentifier("apply-photo-edits")
                }
                .padding(.horizontal, 40)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var originalAspect: CGFloat {
        guard originalImage.size.height > 0 else { return 1 }
        return originalImage.size.width / originalImage.size.height
    }

    private var currentAspect: CGFloat {
        selectedAspect.value(for: workingImage.size, freeformValue: freeformAspect)
    }

    private var effectiveZoom: CGFloat {
        min(max(settledZoom * gestureZoom, 1), 8)
    }

    private func cropWorkspace(size: CGSize) -> some View {
        let cropSize = PhotoCropRenderer.cropFrameSize(in: size, aspectRatio: currentAspect)
        let baseScale = max(
            cropSize.width / workingImage.size.width,
            cropSize.height / workingImage.size.height
        )
        let imageDisplaySize = CGSize(
            width: workingImage.size.width * baseScale * effectiveZoom,
            height: workingImage.size.height * baseScale * effectiveZoom
        )
        let proposedOffset = CGSize(
            width: settledOffset.width + gestureOffset.width,
            height: settledOffset.height + gestureOffset.height
        )
        let visibleOffset = PhotoCropRenderer.clampedOffset(
            proposedOffset,
            imageSize: workingImage.size,
            viewportSize: cropSize,
            zoom: effectiveZoom
        )

        return ZStack {
            Color.black

            Image(uiImage: workingImage)
                .resizable()
                .frame(width: imageDisplaySize.width, height: imageDisplaySize.height)
                .offset(visibleOffset)

            PhotoCropGridOverlay()
                .allowsHitTesting(false)
        }
        .frame(width: cropSize.width, height: cropSize.height)
        .clipShape(Rectangle())
        .overlay(Rectangle().stroke(.white, lineWidth: 2))
        .contentShape(Rectangle())
        .gesture(dragGesture(viewportSize: cropSize))
        .simultaneousGesture(zoomGesture(viewportSize: cropSize))
        .overlay(alignment: .bottomTrailing) {
            if selectedAspect == .freeform {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 1))
                    .offset(x: 12, y: 12)
                    .contentShape(Rectangle())
                    .gesture(freeformResizeGesture(availableSize: size))
                    .accessibilityLabel("Resize freeform crop")
            }
        }
        .onAppear { viewportSize = cropSize }
        .onChange(of: cropSize) { _, newSize in
            viewportSize = newSize
            settledOffset = PhotoCropRenderer.clampedOffset(
                settledOffset,
                imageSize: workingImage.size,
                viewportSize: newSize,
                zoom: settledZoom
            )
        }
    }

    private func cropToolButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dragGesture(viewportSize: CGSize) -> some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let proposedOffset = CGSize(
                    width: settledOffset.width + value.translation.width,
                    height: settledOffset.height + value.translation.height
                )
                settledOffset = PhotoCropRenderer.clampedOffset(
                    proposedOffset,
                    imageSize: workingImage.size,
                    viewportSize: viewportSize,
                    zoom: settledZoom
                )
            }
    }

    private func zoomGesture(viewportSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($gestureZoom) { value, state, _ in
                state = value
            }
            .onEnded { value in
                settledZoom = min(max(settledZoom * value, 1), 8)
                settledOffset = PhotoCropRenderer.clampedOffset(
                    settledOffset,
                    imageSize: workingImage.size,
                    viewportSize: viewportSize,
                    zoom: settledZoom
                )
            }
    }

    private func freeformResizeGesture(availableSize: CGSize) -> some Gesture {
        // The handle moves whenever the crop frame changes size. Measuring the
        // drag in its local coordinates feeds that movement back into the next
        // translation value and makes the frame oscillate under the finger.
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let startingAspect: CGFloat
                if let resizeStartAspect {
                    startingAspect = resizeStartAspect
                } else {
                    startingAspect = freeformAspect
                    resizeStartAspect = startingAspect
                    resetViewport()
                }
                let startingSize = PhotoCropRenderer.cropFrameSize(
                    in: availableSize,
                    aspectRatio: startingAspect
                )
                let proposedWidth = min(
                    availableSize.width,
                    max(96, startingSize.width + value.translation.width * 2)
                )
                let proposedHeight = min(
                    availableSize.height,
                    max(96, startingSize.height + value.translation.height * 2)
                )
                freeformAspect = proposedWidth / proposedHeight
            }
            .onEnded { _ in
                resizeStartAspect = nil
            }
    }

    private func resetViewport() {
        settledZoom = 1
        settledOffset = .zero
    }

    private func applyEdits() {
        guard let croppedImage = PhotoCropRenderer.croppedImage(
            from: workingImage,
            viewportSize: viewportSize,
            zoom: settledZoom,
            offset: settledOffset
        ) else { return }
        onSave(croppedImage)
        dismiss()
    }
}

private struct PhotoCropGridOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                    let x = proxy.size.width * fraction
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))

                    let y = proxy.size.height * fraction
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.32), lineWidth: 0.7)
        }
    }
}
