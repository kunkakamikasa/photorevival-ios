import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct CreateFlowView: View {
    let template: TemplateItem?
    let templates: [TemplateItem]?
    @Binding var credits: Int

    @Environment(\.dismiss) private var dismiss
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @State private var activeTemplate: TemplateItem?
    @State private var selectedMedia: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var selectedVideoImages: [UIImage?]
    @State private var showOptions = false
    @State private var showCredits = false
    @State private var notice: CreationNotice?
    @State private var isCreating = false
    @State private var soundEnabled = false
    @State private var multiShotEnabled = false
    @State private var duration = "5s"
    @State private var videoResolution = "540p"
    @State private var imageResolution = "1k"
    @State private var ratio = "9:16"
    @State private var outputCount = "1"
    @State private var showGenerationFlow = false
    @State private var showLogin = false
    @State private var pendingLoginAction: (() -> Void)?

    init(
        template: TemplateItem?,
        templates: [TemplateItem]? = nil,
        credits: Binding<Int>
    ) {
        self.template = template
        self.templates = templates
        _credits = credits
        _activeTemplate = State(initialValue: template)
        _selectedVideoImages = State(initialValue: Array(repeating: nil, count: max(1, template?.imageUploadCount ?? 1)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperTextureBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        editorContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
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
        .onChange(of: selectedMedia) { _, item in
            loadImage(from: item)
        }
        .onChange(of: selectedVideoItems) { _, items in
            loadVideoImages(items)
        }
        .sheet(isPresented: $showOptions) {
            GenerationOptionsSheet(
                isImageFlow: flow.isImageFlow,
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
            VideoGenerationFlowView(
                title: flow.title,
                templateTitle: activeTemplate?.title ?? template?.title ?? "Generated Video",
                videoName: activeTemplate?.videoName ?? template?.videoName,
                template: activeTemplate ?? template,
                onRegenerate: { showGenerationFlow = false },
                onClose: { showGenerationFlow = false }
            )
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
    }

    @ViewBuilder
    private var editorContent: some View {
        switch flow.family {
        case .videoNoPrompt:
            noPromptVideoEditor
        case .videoPrompt:
            guidedVideoEditor
        case .image:
            imageTemplateEditor
        case .standard:
            guidedVideoEditor
        }
    }

    private var noPromptVideoEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            largeSourcePreview(height: 428)

            templateChooser

            settingsSummary

            creationButton
        }
    }

    private var guidedVideoEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            videoUploadSlots

            promptCard

            settingsSummary

            creationButton

            templateChooser
        }
    }

    private var imageTemplateEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            outputPreview

            Text("Upload Image")
                .font(.title2)
                .foregroundStyle(AppPalette.brownInk)

            sourcePhotoPicker(width: 142, height: 190)
                .frame(maxWidth: .infinity)

            settingsSummary

            creationButton
        }
    }

    private func largeSourcePreview(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            sourceMedia
                .frame(maxWidth: .infinity)
                .frame(height: height)

            LinearGradient(
                colors: [.clear, .black.opacity(0.48)],
                startPoint: .center,
                endPoint: .bottom
            )

            PhotosPicker(selection: $selectedMedia, matching: .images) {
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppPalette.surfaceEdge.opacity(0.70), lineWidth: 1)
        )
    }

    private func sourcePhotoPicker(width: CGFloat, height: CGFloat) -> some View {
        PhotosPicker(selection: $selectedMedia, matching: .images) {
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
    }

    private var outputPreview: some View {
        ZStack {
            if let activeTemplate {
                TemplateMediaView(item: activeTemplate, gravity: .resizeAspect)
                    .frame(maxWidth: .infinity)
                    .frame(height: 316)
            } else {
                ContentUnavailableView("Choose a template", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .frame(height: 316)
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
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
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

    private var promptCard: some View {
        ScrollView(.vertical) {
            Text(flow.prompt)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(16)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        .frame(height: 150, alignment: .top)
        .background(Color(.systemBackground).opacity(0.70), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppPalette.surfaceEdge.opacity(0.72), lineWidth: 1)
        )
        .accessibilityLabel("Generation prompt")
    }

    private var templateChooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Template")
                .font(.title2.bold())
                .foregroundStyle(AppPalette.ink)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(flow.templates) { item in
                        let thumbnailWidth: CGFloat = flow.family == .videoNoPrompt ? 150 : 158
                        let thumbnailHeight: CGFloat = flow.family == .videoNoPrompt ? 150 : 214

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectTemplate(item)
                            }
                        } label: {
                            ZStack(alignment: .bottom) {
                                TemplateMediaView(item: item, gravity: .resizeAspectFill)
                                    .frame(
                                        width: thumbnailWidth,
                                        height: thumbnailHeight,
                                        alignment: flow.family == .videoNoPrompt ? .top : .center
                                    )
                                    .clipped()

                                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)

                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .padding(8)
                            }
                            .frame(width: thumbnailWidth, height: thumbnailHeight)
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
        }
    }

    private var settingsSummary: some View {
        Button {
            showOptions = true
        } label: {
            HStack(spacing: 9) {
                if flow.isImageFlow {
                    parameterPill("\(outputCount) Img")
                    parameterPill(imageResolution)
                    parameterPill(ratio)
                } else {
                    Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .frame(width: 34, height: 34)
                        .background(AppPalette.backgroundTop, in: Circle())
                    Image(systemName: multiShotEnabled ? "video.badge.waveform.fill" : "video.slash.fill")
                        .frame(width: 34, height: 34)
                        .background(AppPalette.backgroundTop, in: Circle())
                    parameterPill(duration)
                    parameterPill(videoResolution)
                    if flow.family != .videoNoPrompt {
                        parameterPill(ratio)
                    }
                }

                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .foregroundStyle(AppPalette.surfaceEdge)
            .padding(.horizontal, 14)
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

    private func parameterPill(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(AppPalette.backgroundTop, in: Capsule())
    }

    private var creationButton: some View {
        Button {
            requireLogin {
                guard credits >= flow.cost else {
                    showCredits = true
                    return
                }

                credits -= flow.cost
                if flow.isImageFlow {
                    isCreating = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(850))
                        isCreating = false
                        notice = .queued
                    }
                } else {
                    showGenerationFlow = true
                }
            }
        } label: {
            ZStack {
                if isCreating {
                    ProgressView()
                        .tint(.white)
                } else {
                    VStack(spacing: 0) {
                        Text(credits >= flow.cost ? "Create" : "More Credits")
                            .font(.title3.bold())
                        if credits < flow.cost {
                            Text("Not enough credits")
                                .font(.caption)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Label("\(flow.cost)", systemImage: "diamond.fill")
                        .font(.headline)
                        .foregroundStyle(Color.yellow)
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

    private func requireLogin(_ action: @escaping () -> Void) {
        guard isLoggedIn || ProcessInfo.processInfo.arguments.contains("-loggedIn") else {
            pendingLoginAction = action
            showLogin = true
            return
        }
        action()
    }

    private func loadImage(from item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                selectedImage = image
            }
        }
    }

    private func loadVideoImages(_ items: [PhotosPickerItem]) {
        Task {
            var images = Array(repeating: nil, count: flow.imageUploadCount) as [UIImage?]
            for (index, item) in items.prefix(flow.imageUploadCount).enumerated() {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                if images.indices.contains(index) {
                    images[index] = image
                }
            }
            await MainActor.run { selectedVideoImages = images }
        }
    }

    private func selectTemplate(_ item: TemplateItem) {
        activeTemplate = item
        let count = max(1, item.imageUploadCount)
        if selectedVideoImages.count != count {
            selectedVideoImages = Array((selectedVideoImages + Array(repeating: nil, count: count)).prefix(count))
        }
        selectedVideoItems = Array(selectedVideoItems.prefix(count))
    }

    private var videoUploadSlots: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 14
            let uploadCount = flow.imageUploadCount
            let availableWidth = proxy.size.width - spacing * CGFloat(max(0, uploadCount - 1))
            let slotWidth = uploadCount == 1
                ? min(166, proxy.size.width)
                : availableWidth / CGFloat(uploadCount)

            PhotosPicker(
                selection: $selectedVideoItems,
                maxSelectionCount: uploadCount,
                matching: .images
            ) {
                HStack(spacing: spacing) {
                    ForEach(0..<uploadCount, id: \.self) { index in
                        ImageGenerationUploadSlot(
                            image: selectedVideoImages.indices.contains(index) ? selectedVideoImages[index] : nil,
                            label: "Image\(index + 1)",
                            fallbackItem: activeTemplate
                        )
                        .frame(width: slotWidth, height: 214)
                        .accessibilityIdentifier("video-image-upload-slot-\(index + 1)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 214)
    }

    private var flow: CreationFlowConfiguration {
        CreationFlowConfiguration(template: activeTemplate ?? template, templateOptions: templates)
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
    @Binding var soundEnabled: Bool
    @Binding var multiShotEnabled: Bool
    @Binding var duration: String
    @Binding var videoResolution: String
    @Binding var imageResolution: String
    @Binding var ratio: String
    @Binding var outputCount: String

    @Environment(\.dismiss) private var dismiss

    private let ratios = ["16:9", "9:16", "1:1", "4:3", "3:4", "3:2", "2:3", "21:9"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isImageFlow {
                        optionSection("Resolution", values: ["1k"], selection: $imageResolution, columns: 3)
                        optionSection("Ratio", values: ratios, selection: $ratio, columns: 3)
                        optionSection("Output Image Number", values: ["1", "2", "4"], selection: $outputCount, columns: 3)
                    } else {
                        binarySection(
                            "Sounds",
                            offIcon: "speaker.slash.fill",
                            onIcon: "speaker.wave.2.fill",
                            isOn: $soundEnabled
                        )
                        binarySection(
                            "Multi-Shot Video",
                            offIcon: "video.slash.fill",
                            onIcon: "video.badge.waveform.fill",
                            isOn: $multiShotEnabled
                        )
                        optionSection("Duration", values: ["5s", "8s", "10s"], selection: $duration, columns: 3)
                        optionSection(
                            "Resolution",
                            values: ["540p", "720p", "1080p"],
                            selection: $videoResolution,
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

    var cost: Int {
        switch family {
        case .videoNoPrompt: max(template?.estimatedCredits ?? 0, 40)
        case .videoPrompt: max(template?.estimatedCredits ?? 0, 50)
        case .image: 30
        case .standard: 50
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
            template?.promptTemplate ?? "Use the uploaded image as the visual reference and preserve the subject's identity throughout the video."
        case .image:
            "Use the uploaded image as the visual reference and apply the selected illustrated style while preserving the subject and composition."
        case .standard:
            "Use the uploaded image as the source. Keep the subject recognizable and apply the selected template with natural detail and motion."
        }
    }

    var isImageFlow: Bool { family == .image }
    var showsHelp: Bool { family == .videoNoPrompt }
    var imageUploadCount: Int { template?.imageUploadCount ?? 1 }
}

private enum VideoGenerationStage: Equatable {
    case loading
    case result
    case saved
}

private struct VideoGenerationFlowView: View {
    let title: String
    let templateTitle: String
    let videoName: String?
    let template: TemplateItem?
    let onRegenerate: () -> Void
    let onClose: () -> Void

    @State private var stage: VideoGenerationStage = .loading
    @State private var selectedTab: AppTab = .me
    @State private var showPreview = false
    @State private var showPaywall = false

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
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if stage != .saved {
                BottomTabBar(selection: $selectedTab)
                    .allowsHitTesting(false)
            }
        }
        .task(id: stage) {
            guard stage == .loading else { return }
            // Keep the loading state visible long enough for the generation handoff to be observable.
            try? await Task.sleep(for: .milliseconds(2_400))
            guard !Task.isCancelled, stage == .loading else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                stage = .result
            }
        }
        .fullScreenCover(isPresented: $showPreview) {
            VideoGenerationPreviewView(
                videoName: videoName,
                template: template,
                onClose: { showPreview = false },
                onRegenerate: {
                    showPreview = false
                    onRegenerate()
                },
                onSave: {
                    showPreview = false
                    stage = .saved
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
            MembershipPaywallView()
        }
        .preferredColorScheme(.light)
    }

    private var workspaceHeader: some View {
        HStack(spacing: 14) {
            HStack(spacing: 0) {
                Text("Video")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 82, height: 43)
                    .background(Color.white.opacity(0.42), in: Capsule())

                Text("Photo")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .frame(width: 82, height: 43)
            }
            .padding(3)
            .background(Color.white.opacity(0.24), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.68), lineWidth: 1))

            Spacer(minLength: 0)

            Button(action: onClose) {
                Text("Delete")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
                    .padding(.horizontal, 20)
                    .frame(height: 43)
                    .background(Color.white.opacity(0.48), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete generation")

            Button {} label: {
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
    }

    private var resultContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                workspaceHeader

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: 25, weight: .heavy))
                            .foregroundStyle(AppPalette.ink)
                        Text(templateTitle)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AppPalette.brownInk)
                    }
                    Spacer()
                    Text("Today")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppPalette.brownInk)
                }
                .padding(.horizontal, 20)
                .padding(.top, 53)

                generatedVideoCard
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                HStack(spacing: 0) {
                    Button {
                        stage = .saved
                    } label: {
                        Label("Save", systemImage: "arrow.down.to.line")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(AppPalette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save generated video")

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
        }
        .scrollIndicators(.hidden)
    }

    private var generatedVideoCard: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black

            generationMedia(gravity: .resizeAspect)

            VideoWatermarkPattern()
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
            .padding(12)
            .accessibilityLabel("Maximize generated video")
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

            HStack(spacing: 18) {
                VideoShareIcon(symbol: "message.fill", color: Color(red: 0.08, green: 0.78, blue: 0.27), label: "WhatsApp")
                VideoShareIcon(symbol: "bubble.left.and.bubble.right.fill", color: Color(red: 0.11, green: 0.81, blue: 0.25), label: "Messages")
                VideoShareIcon(symbol: "bolt.horizontal.circle.fill", color: Color(red: 0.43, green: 0.36, blue: 0.97), label: "Messenger")
                VideoShareIcon(symbol: "f.cursive", color: Color(red: 0.06, green: 0.37, blue: 0.95), label: "Facebook")
                VideoShareIcon(symbol: "camera.fill", color: Color(red: 0.90, green: 0.15, blue: 0.54), label: "Instagram")
                VideoShareIcon(symbol: "music.note", color: .black, label: "TikTok")
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

            ZStack(alignment: .bottomTrailing) {
                generationMedia(gravity: .resizeAspectFill)
                Text("Photo Revive AI")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .italic()
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(15)
            }
            .frame(width: 244, height: 432)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppPalette.surfaceEdge.opacity(0.74), lineWidth: 1))
            .padding(.top, 55)

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

            Spacer(minLength: 26)

            HStack(spacing: 21) {
                VideoShareIcon(symbol: "message.fill", color: Color(red: 0.08, green: 0.78, blue: 0.27), label: "WhatsApp")
                VideoShareIcon(symbol: "bubble.left.and.bubble.right.fill", color: Color(red: 0.11, green: 0.81, blue: 0.25), label: "Messages")
                VideoShareIcon(symbol: "bolt.horizontal.circle.fill", color: Color(red: 0.43, green: 0.36, blue: 0.97), label: "Messenger")
                VideoShareIcon(symbol: "f.cursive", color: Color(red: 0.06, green: 0.37, blue: 0.95), label: "Facebook")
                VideoShareIcon(symbol: "camera.fill", color: Color(red: 0.90, green: 0.15, blue: 0.54), label: "Instagram")
                VideoShareIcon(symbol: "music.note", color: .black, label: "TikTok")
            }
            .padding(.bottom, 28)
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
    private func generationMedia(gravity: AVLayerVideoGravity) -> some View {
        if let template {
            TemplateMediaView(item: template, gravity: gravity)
        } else if let videoName {
            LoopingVideoView(resourceName: videoName, videoGravity: gravity)
        } else {
            Color.black
        }
    }
}

private struct VideoGenerationPreviewView: View {
    let videoName: String?
    let template: TemplateItem?
    let onClose: () -> Void
    let onRegenerate: () -> Void
    let onSave: () -> Void
    let onRemoveWatermark: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            previewMedia
                .ignoresSafeArea(edges: .horizontal)

            VideoWatermarkPattern()
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
                    previewAction("eraser", label: "Remove watermark", action: onRemoveWatermark)
                    previewAction("square.and.arrow.up", label: "Share generated video", accent: true, action: {})
                }
                .padding(.trailing, 20)
            }
            .padding(.top, 160)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var previewMedia: some View {
        if let template {
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

private struct VideoWatermarkPattern: View {
    private let placements: [(CGFloat, CGFloat)] = [
        (0.13, 0.17), (0.55, 0.20), (0.86, 0.34),
        (0.23, 0.50), (0.67, 0.57), (0.11, 0.77), (0.73, 0.83)
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(placements.enumerated()), id: \.offset) { _, placement in
                Text("Photo Revive AI")
                    .font(.system(size: max(12, proxy.size.width * 0.05), weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .rotationEffect(.degrees(-18))
                    .position(
                        x: proxy.size.width * placement.0,
                        y: proxy.size.height * placement.1
                    )
            }
        }
    }
}

private struct VideoShareIcon: View {
    let symbol: String
    let color: Color
    let label: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 21, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 45, height: 45)
            .background(color, in: Circle())
            .accessibilityLabel(label)
    }
}

struct FixedFeatureView: View {
    let feature: FixedFeature
    @Binding var credits: Int

    var body: some View {
        switch feature {
        case .oneTapRestore:
            FixedPhotoRestoreFeature(kind: .restore, credits: $credits)
        case .enhancePhoto:
            FixedPhotoRestoreFeature(kind: .enhance, credits: $credits)
        case .enhanceVideo:
            FixedVideoEnhanceFeature(credits: $credits)
        case .photoToVideo:
            FixedVideoGeneratorFeature(initialMode: .image, credits: $credits)
        case .textToVideo:
            FixedVideoGeneratorFeature(initialMode: .text, credits: $credits)
        case .aiImage:
            FixedAIImageFeature(credits: $credits)
        case .fusion:
            FixedFusionFeature(credits: $credits)
        case .imageToImage:
            FixedAIImageFeature(credits: $credits, initialMode: .image)
        case .textToImage:
            FixedAIImageFeature(credits: $credits, initialMode: .text)
        }
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
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(AppPalette.ink)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.58), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer(minLength: 0)

                if showsHelp {
                    Button(action: onHelp) {
                        Image(systemName: "questionmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.58), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
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

private struct FixedFeatureScaffold<Content: View, Footer: View>: View {
    let title: String
    let showsHelp: Bool
    let onBack: () -> Void
    let onHelp: () -> Void
    let content: Content
    let footer: Footer

    init(
        title: String,
        showsHelp: Bool = false,
        onBack: @escaping () -> Void,
        onHelp: @escaping () -> Void = {},
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.showsHelp = showsHelp
        self.onBack = onBack
        self.onHelp = onHelp
        self.content = content()
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

                    ScrollView {
                        content
                            .frame(width: max(0, proxy.size.width - 40), alignment: .leading)
                            .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)

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

private enum FixedPhotoFeatureKind: Equatable {
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

    var cost: Int {
        switch self {
        case .restore: 35
        case .enhance: 15
        }
    }
}

private struct FixedPhotoRestoreFeature: View {
    let kind: FixedPhotoFeatureKind
    @Binding var credits: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showTips = false
    @State private var showCredits = false
    @State private var showDraftWarning = false
    @State private var showCrop = false

    var body: some View {
        ZStack {
            FixedFeatureScaffold(
                title: kind.title,
                showsHelp: true,
                onBack: requestDismiss,
                onHelp: { showTips = true }
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ZStack(alignment: .bottom) {
                            if selectedImage == nil {
                                Image(kind == .restore ? "RestoreFeatureCard" : "EnhanceFeatureCard")
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                restorePreview

                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.42)],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )

                                HStack(spacing: 12) {
                                    FeatureAddPhotoIcon()
                                        .frame(width: 31, height: 31)
                                    Text("Change Photo")
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
                        .aspectRatio(1168.0 / 1560.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
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
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(AppPalette.ink)

                    FeatureTipRow(kind: kind)
                }
            } footer: {
                FeaturePrimaryButton(
                    title: "Generate",
                    cost: kind.cost,
                    credits: $credits,
                    onNeedCredits: { showCredits = true },
                    onCreate: {}
                )
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
        .fullScreenCover(isPresented: $showCrop) {
            if let selectedImage {
                FeaturePhotoCropView(image: selectedImage)
            }
        }
        .onChange(of: selectedItem) { _, item in
            loadImage(item)
        }
    }

    @ViewBuilder
    private var restorePreview: some View {
        if let selectedImage {
            Image(uiImage: selectedImage)
                .resizable()
                .scaledToFill()
        } else {
            Image(kind == .restore ? "RestoreFeatureCard" : "EnhanceFeatureCard")
                .resizable()
                .scaledToFill()
        }
    }

    private func loadImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await MainActor.run { selectedImage = image }
        }
    }

    private func requestDismiss() {
        if selectedImage != nil {
            showDraftWarning = true
        } else {
            dismiss()
        }
    }
}

private struct FeatureTipRow: View {
    let kind: FixedPhotoFeatureKind

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
                VStack(spacing: 8) {
                    Image(item.0)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    Image(systemName: item.2 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 25, weight: .bold))
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
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(AppPalette.ink)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                }

                Text(kind.tipsTitle)
                    .font(.system(size: 27, weight: .heavy))
                    .foregroundStyle(AppPalette.ink)
                    .multilineTextAlignment(.center)

                tipSection(
                    title: "Recommended",
                    subtitle: kind == .restore ? "Damaged, faded, or blurry photo" : "Blurry or unclear photo",
                    names: kind == .restore ? ["MemoryPortrait", "Gentleman"] : ["MemoryPortrait", "AnimePortrait"],
                    color: Color(red: 0.58, green: 0.69, blue: 0.40),
                    icon: "checkmark.circle.fill"
                )

                tipSection(
                    title: "Not Recommended",
                    subtitle: kind == .restore ? "Clear Photo" : "Clear or damaged photos will not produce effective results",
                    names: kind == .restore ? ["Fashion", "Cowboy"] : ["CartoonPortrait", "Cowboy"],
                    color: Color(red: 0.88, green: 0.26, blue: 0.20),
                    icon: "xmark.circle.fill"
                )

                Button(action: onDismiss) {
                    Text("Continue")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.88, blue: 0.62))
                        .frame(maxWidth: .infinity)
                        .frame(height: 59)
                        .background(.black.opacity(0.92), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 22)
        }
    }

    private func tipSection(title: String, subtitle: String, names: [String], color: Color, icon: String) -> some View {
        VStack(spacing: 9) {
            Label(title, systemImage: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.system(size: 16))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                ForEach(names, id: \.self) { name in
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 104, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
            }
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
                if cost > 0 { credits -= cost }
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

private struct FixedVideoEnhanceFeature: View {
    @Binding var credits: Int
    @Environment(\.dismiss) private var dismiss
    @State private var showChooser = false
    @State private var showSystemPicker = false
    @State private var selectedVideo: PhotosPickerItem?
    @State private var showCredits = false
    @State private var showDraftWarning = false

    var body: some View {
        ZStack {
            FixedFeatureScaffold(
                title: "Enhance Video",
                onBack: requestDismiss
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    FeatureVideoSourceCard(
                        title: selectedVideo == nil ? "Choose Video" : "Change Video",
                        detail: "Max 100 MB • Up to 30 sec • Up to 4K",
                        imageName: selectedVideo == nil ? nil : "SchoolWaveLandscape",
                        action: { showChooser = true }
                    )

                    HStack {
                        Text("4K")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppPalette.surfaceEdge)
                            .padding(.horizontal, 17)
                            .frame(height: 34)
                            .background(Color.white.opacity(0.45), in: Capsule())
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.44), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppPalette.surfaceEdge.opacity(0.72), lineWidth: 1.2))

                    Text("Examples")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppPalette.ink)

                    Image("EnhanceVideoExamples")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                FeaturePrimaryButton(
                    title: "Generate",
                    cost: 0,
                    credits: $credits,
                    onNeedCredits: {},
                    onCreate: {}
                )
            }

            if showDraftWarning {
                FeatureDraftWarningOverlay(onConfirm: { dismiss() }, onCancel: { showDraftWarning = false })
                    .zIndex(2)
            }
        }
        .sheet(isPresented: $showChooser) {
            FeatureVideoChooser(
                onChooseFromPhotos: {
                    showChooser = false
                    showSystemPicker = true
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .photosPicker(isPresented: $showSystemPicker, selection: $selectedVideo, matching: .videos)
    }

    private func requestDismiss() {
        if selectedVideo != nil { showDraftWarning = true } else { dismiss() }
    }
}

private struct FeatureVideoSourceCard: View {
    let title: String
    let detail: String
    let imageName: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.38)
                }

                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        FeatureAddPhotoIcon()
                            .frame(width: 31, height: 31)
                        Text(title)
                            .font(.system(size: 21, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 25)
                            .frame(height: 54)
                            .background(.black.opacity(0.44), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.82), lineWidth: 1.5))

                    Text(detail)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppPalette.brownInk)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppPalette.surfaceEdge.opacity(0.72), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }
}

private struct FeatureVideoChooser: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    let onChooseFromPhotos: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Choose Video")
                    .font(.system(size: 27, weight: .heavy))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 23, weight: .medium))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                chooserTab("Uploaded", index: 0)
                chooserTab("Created", index: 1)
            }
            .padding(4)
            .background(Color(red: 1, green: 0.96, blue: 0.87), in: RoundedRectangle(cornerRadius: 14))

            if tab == 0 {
                Button(action: onChooseFromPhotos) {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 44, weight: .regular))
                        Text("Choose\nfrom Photos")
                            .font(.system(size: 20, weight: .regular))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
                    .frame(height: 205)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 36))
                    Image(systemName: "hand.draw")
                        .font(.system(size: 70, weight: .light))
                    Text("There is nothing now")
                        .font(.system(size: 20))
                }
                .foregroundStyle(.gray.opacity(0.68))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .background(.white)
    }

    private func chooserTab(_ title: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { tab = index }
        } label: {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tab == index ? AppPalette.ink : .gray)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(tab == index ? Color(red: 1, green: 0.76, blue: 0.36) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private enum FixedVideoGeneratorMode: Hashable {
    case image
    case text
}

private struct FixedVideoGeneratorFeature: View {
    let initialMode: FixedVideoGeneratorMode
    @Binding var credits: Int
    @Environment(\.dismiss) private var dismiss
    @State private var mode: FixedVideoGeneratorMode
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var prompt = ""
    @State private var showSettings = false
    @State private var showCredits = false
    @State private var showDraftWarning = false
    @State private var showCrop = false
    @State private var soundEnabled = false
    @State private var multiShotEnabled = false
    @State private var duration = "5s"
    @State private var resolution = "540p"
    @State private var ratio = "9:16"
    @State private var showGenerationFlow = false

    init(initialMode: FixedVideoGeneratorMode, credits: Binding<Int>, initialImage: UIImage? = nil) {
        self.initialMode = initialMode
        _credits = credits
        _mode = State(initialValue: initialMode)
        _selectedImage = State(initialValue: initialImage)
    }

    var body: some View {
        ZStack {
            FixedFeatureScaffold(
                title: "Video Generator",
                showsHelp: true,
                onBack: requestDismiss
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    FeatureModeTabs(
                        options: [("Image to Video", .image), ("Text To Video", .text)],
                        selection: $mode
                    )

                    if mode == .image {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            FeatureVideoGeneratorPreview(
                                image: selectedImage,
                                fallbackImageName: "PhotoToVideoExample",
                                fallbackVideoName: nil,
                                prompt: selectedImage == nil ? "" : "Using uploaded subject, keep exact appearance, riding motorcycle on city street, goggles"
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
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
                            fallbackImageName: "TextToVideoExample",
                            fallbackVideoName: nil,
                            prompt: ""
                        )
                        .padding(.horizontal, 20)
                    }

                    FeaturePromptBox(
                        text: $prompt,
                        placeholder: mode == .image ? "Describe motion you want to add to your photo" : "Describe your video vision here"
                    )

                    FeatureSettingsSummary(
                        values: [soundEnabled ? "sound" : "mute", multiShotEnabled ? "multi" : "single", duration, resolution, mode == .text ? ratio : nil].compactMap { $0 },
                        onTap: { showSettings = true }
                    )
                }
            } footer: {
                FeaturePrimaryButton(
                    title: "Generate",
                    cost: 40,
                    credits: $credits,
                    onNeedCredits: { showCredits = true },
                    onCreate: { showGenerationFlow = true }
                )
            }

            if showDraftWarning {
                FeatureDraftWarningOverlay(onConfirm: { dismiss() }, onCancel: { showDraftWarning = false })
                    .zIndex(2)
            }
        }
        .onChange(of: selectedItem) { _, item in loadImage(item) }
        .sheet(isPresented: $showSettings) {
            FeatureSettingsSheet(
                mode: .video,
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
            VideoGenerationFlowView(
                title: "Video Generator",
                templateTitle: mode == .image ? "Photo To Video" : "Text To Video",
                videoName: mode == .text ? "text_to_video_whale_cover" : "school_wave",
                template: nil,
                onRegenerate: { showGenerationFlow = false },
                onClose: { showGenerationFlow = false }
            )
        }
        .fullScreenCover(isPresented: $showCrop) {
            if let selectedImage { FeaturePhotoCropView(image: selectedImage) }
        }
    }

    private func loadImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
            await MainActor.run { selectedImage = image }
        }
    }

    private func requestDismiss() {
        if selectedImage != nil || !prompt.isEmpty { showDraftWarning = true } else { dismiss() }
    }
}

private struct FeatureVideoGeneratorPreview: View {
    let image: UIImage?
    let fallbackImageName: String
    let fallbackVideoName: String?
    let prompt: String

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let fallbackVideoName {
                    LoopingVideoView(resourceName: fallbackVideoName, videoGravity: .resizeAspectFill)
                        .allowsHitTesting(false)
                } else {
                    Image(fallbackImageName).resizable().scaledToFill()
                }
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
        .aspectRatio(1048.0 / 1253.0, contentMode: .fit)
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

private struct FeaturePromptBox: View {
    @Binding var text: String
    let placeholder: String
    var height: CGFloat = 152

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppPalette.surfaceEdge.opacity(0.78))
                    .padding(.horizontal, 18)
                    .padding(.top, 17)
            }

            TextEditor(text: $text)
                .font(.system(size: 18))
                .foregroundStyle(AppPalette.brownInk)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .scrollContentBackground(.hidden)

            Text("\(text.count)/2000")
                .font(.system(size: 14))
                .foregroundStyle(AppPalette.surfaceEdge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(16)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppPalette.surfaceEdge.opacity(0.72), lineWidth: 1.2))
    }
}

private struct FeatureSettingsSummary: View {
    let values: [String]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    if value == "mute" {
                        Image(systemName: "speaker.slash.fill")
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.35), in: Circle())
                    } else if value == "sound" {
                        Image(systemName: "speaker.wave.2.fill")
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.35), in: Circle())
                    } else if value == "single" {
                        Image(systemName: "video.slash.fill")
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.35), in: Circle())
                    } else if value == "multi" {
                        Image(systemName: "video.badge.waveform.fill")
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.35), in: Circle())
                    } else {
                        Text(value)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppPalette.surfaceEdge)
                            .padding(.horizontal, 11)
                            .frame(height: 36)
                            .background(Color.white.opacity(0.35), in: Capsule())
                    }
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppPalette.surfaceEdge)
            }
            .padding(.horizontal, 15)
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
    @Binding var credits: Int

    @Environment(\.dismiss) private var dismiss
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @AppStorage("hasAcceptedImageAIDataNotice") private var hasAcceptedDataNotice = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage?]
    @State private var resolution = "1k"
    @State private var ratio = "9:16"
    @State private var outputCount = "1"
    @State private var showSettings = false
    @State private var showDataNotice = false
    @State private var showGenerationFlow = false
    @State private var showLogin = false
    @State private var pendingLoginAction: (() -> Void)?

    init(template: TemplateItem, credits: Binding<Int>) {
        self.template = template
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
            ) {
                VStack(alignment: .leading, spacing: 17) {
                    templatePreview

                    Text("Upload Image")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(AppPalette.ink)

                    uploadSlots

                    FeatureSettingsSummary(
                        values: ["\(outputCount) Img", resolution, ratio],
                        onTap: { showSettings = true }
                    )
                }
                .accessibilityIdentifier("image-generation-upload")
            } footer: {
                ImageGenerationPrimaryButton(action: beginGeneration)
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
        .onChange(of: selectedItems) { _, items in
            loadImages(items)
        }
        .sheet(isPresented: $showSettings) {
            FeatureSettingsSheet(
                mode: .image,
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
            ImageGenerationFlowView(
                title: template.title,
                template: template,
                credits: $credits,
                onClose: {
                    showGenerationFlow = false
                    dismiss()
                }
            )
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
        .preferredColorScheme(.light)
    }

    private var templatePreview: some View {
        ZStack(alignment: .bottom) {
            TemplateMediaView(item: template, gravity: .resizeAspectFill)
                .blur(radius: 22)
                .scaleEffect(1.18)

            Color.white.opacity(0.31)

            TemplateMediaView(item: template, gravity: .resizeAspect)

            HStack(spacing: 10) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
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
        .frame(height: 302)
        .background(Color(.systemGray4))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppPalette.surfaceEdge.opacity(0.88), lineWidth: 1.2)
        )
        .clipped()
    }

    private var uploadSlots: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 14
            let uploadCount = template.imageUploadCount
            let availableWidth = proxy.size.width - spacing * CGFloat(max(0, uploadCount - 1))
            let slotWidth = uploadCount == 1
                ? min(151, proxy.size.width)
                : availableWidth / CGFloat(uploadCount)

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: uploadCount,
                matching: .images
            ) {
                HStack(spacing: spacing) {
                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                        ImageGenerationUploadSlot(
                            image: image,
                            label: "Image\(index + 1)"
                        )
                        .frame(width: slotWidth)
                        .accessibilityIdentifier("image-upload-slot-\(index + 1)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 188)
    }

    private func beginGeneration() {
        requireLogin {
            if hasAcceptedDataNotice {
                showGenerationFlow = true
            } else {
                showDataNotice = true
            }
        }
    }

    private func requireLogin(_ action: @escaping () -> Void) {
        guard isLoggedIn || ProcessInfo.processInfo.arguments.contains("-loggedIn") else {
            pendingLoginAction = action
            showLogin = true
            return
        }
        action()
    }

    private func acceptNoticeAndGenerate() {
        hasAcceptedDataNotice = true
        showDataNotice = false
        showGenerationFlow = true
    }

    private func loadImages(_ items: [PhotosPickerItem]) {
        Task {
            var images = selectedImages
            for (index, item) in items.prefix(template.imageUploadCount).enumerated() {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                if images.indices.contains(index) {
                    images[index] = image
                }
            }
            await MainActor.run { selectedImages = images }
        }
    }
}

private struct ImageGenerationPrimaryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text("Generate")
                    .font(.system(size: 26, weight: .heavy))

                HStack(spacing: 5) {
                    Spacer()
                    Image("RewardsCreditToken")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text("--")
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
    }
}

private struct ImageGenerationUploadSlot: View {
    let image: UIImage?
    let label: String
    let fallbackItem: TemplateItem?

    init(image: UIImage?, label: String, fallbackItem: TemplateItem? = nil) {
        self.image = image
        self.label = label
        self.fallbackItem = fallbackItem
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let fallbackItem {
                TemplateFirstFrameView(item: fallbackItem)
            } else {
                Color(.systemGray4)
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 33, weight: .medium))
                    .foregroundStyle(AppPalette.surfaceEdge)
            }

            if image != nil || fallbackItem != nil {
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

                    Image(systemName: "crop")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 31, height: 31)
                        .background(.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 5))
                }
                .foregroundStyle(.white)
                .padding(7)
            }
        }
        .frame(height: 188)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(AppPalette.surfaceEdge.opacity(0.90), lineWidth: 1.1)
        )
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
                AsyncImage(url: coverImageURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.systemGray4)
                    }
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
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Image("RewardsBellIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .offset(y: -48)
                    .padding(.bottom, -34)

                Text("AI Data Processing\nNotice")
                    .font(.system(size: 25, weight: .heavy))
                    .foregroundStyle(AppPalette.brownInk)
                    .multilineTextAlignment(.center)

                Text("""
                To generate images, your selected photos and input data will be sent to our servers and may be processed by third-party AI service providers.

                Data shared includes:
                • Selected photos
                • Generation parameters (e.g. prompts, styles)

                Purpose:
                Your data is used only to generate the requested content and is not used for training or unrelated purposes.

                By tapping “Agree and Continue”, you agree to this data processing and sharing.
                """)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppPalette.brownInk)
                .padding(.top, 18)

                Button(action: onAgree) {
                    Text("Agree and Continue")
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AppPalette.orange, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 20)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppPalette.surfaceEdge)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 21)
            .padding(.bottom, 11)
            .background(Color(red: 1.0, green: 0.97, blue: 0.89), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppPalette.surfaceEdge.opacity(0.92), lineWidth: 1.4)
            )
            .padding(.horizontal, 43)
            .accessibilityIdentifier("image-ai-data-notice")
        }
    }
}

private enum ImageGenerationStage: Equatable {
    case loading
    case result
    case detail
    case saved
}

private struct ImageGenerationFlowView: View {
    let title: String
    let template: TemplateItem
    @Binding var credits: Int
    let onClose: () -> Void

    @State private var stage = ImageGenerationStage.loading
    @State private var selectedTab = AppTab.me
    @State private var showPaywall = false
    @State private var showVideoGenerator = false

    private var generatedImage: UIImage? {
        template.imageName.isEmpty ? nil : UIImage(named: template.imageName)
    }

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
                case .detail:
                    EmptyView()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if stage == .loading || stage == .result {
                BottomTabBar(selection: $selectedTab)
                    .allowsHitTesting(false)
            }
        }
        .task(id: stage) {
            guard stage == .loading else { return }
            try? await Task.sleep(for: .milliseconds(2_400))
            guard !Task.isCancelled, stage == .loading else { return }
            withAnimation(.easeInOut(duration: 0.24)) { stage = .result }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            MembershipPaywallView()
        }
        .fullScreenCover(isPresented: $showVideoGenerator) {
            FixedVideoGeneratorFeature(
                initialMode: .image,
                credits: $credits,
                initialImage: generatedImage
            )
        }
        .preferredColorScheme(stage == .detail ? .dark : .light)
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
                        TemplateMediaView(item: template, gravity: .resizeAspectFill)

                        if stage == .loading {
                            Color.black.opacity(0.50)
                            VStack(spacing: 18) {
                                VideoGenerationDots()
                                Text("Please wait\n(1-3 min)")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.32))
                                    .multilineTextAlignment(.center)
                            }
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

    private var imageWorkspaceHeader: some View {
        HStack {
            HStack(spacing: 0) {
                Text("Video")
                    .foregroundStyle(AppPalette.ink)
                    .frame(width: 72, height: 40)
                Text("Photo")
                    .foregroundStyle(AppPalette.accent.opacity(0.84))
                    .frame(width: 72, height: 40)
                    .background(Color.white.opacity(0.45), in: Capsule())
            }
            .font(.system(size: 18, weight: .bold))
            .padding(2)
            .background(Color.white.opacity(0.20), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.68), lineWidth: 1))

            Spacer()

            Button(action: onClose) {
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
                .padding(.horizontal, 20)

                TemplateMediaView(item: template, gravity: .resizeAspect)
                    .frame(maxWidth: .infinity, maxHeight: 557)
                    .padding(.horizontal, 48)
                    .padding(.top, 17)

                HStack(spacing: 14) {
                    Button {
                        stage = .loading
                    } label: {
                        Label("Recreate", systemImage: "arrow.clockwise")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.white, in: Capsule())
                    }

                    Button {
                        stage = .saved
                    } label: {
                        Label("Save", systemImage: "arrow.down.to.line")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(AppPalette.accent, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 19)

                Text("Share to:")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                HStack(spacing: 18) {
                    VideoShareIcon(symbol: "message.fill", color: Color(red: 0.08, green: 0.78, blue: 0.27), label: "WhatsApp")
                    VideoShareIcon(symbol: "bubble.left.and.bubble.right.fill", color: Color(red: 0.11, green: 0.81, blue: 0.25), label: "Messages")
                    VideoShareIcon(symbol: "bolt.horizontal.circle.fill", color: Color(red: 0.43, green: 0.36, blue: 0.97), label: "Messenger")
                    VideoShareIcon(symbol: "f.cursive", color: Color(red: 0.06, green: 0.37, blue: 0.95), label: "Facebook")
                    VideoShareIcon(symbol: "camera.fill", color: Color(red: 0.90, green: 0.15, blue: 0.54), label: "Instagram")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
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

                TemplateMediaView(item: template, gravity: .resizeAspect)
                    .frame(width: 212, height: 378)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, 12)

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

                Text("Share to:")
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(AppPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                HStack(spacing: 18) {
                    VideoShareIcon(symbol: "message.fill", color: Color(red: 0.08, green: 0.78, blue: 0.27), label: "WhatsApp")
                    VideoShareIcon(symbol: "bubble.left.and.bubble.right.fill", color: Color(red: 0.11, green: 0.81, blue: 0.25), label: "Messages")
                    VideoShareIcon(symbol: "bolt.horizontal.circle.fill", color: Color(red: 0.43, green: 0.36, blue: 0.97), label: "Messenger")
                    VideoShareIcon(symbol: "f.cursive", color: Color(red: 0.06, green: 0.37, blue: 0.95), label: "Facebook")
                    VideoShareIcon(symbol: "camera.fill", color: Color(red: 0.90, green: 0.15, blue: 0.54), label: "Instagram")
                }
                .padding(.horizontal, 20)
                .padding(.top, 11)

                Text("What's next? Try these:")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(AppPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ImageGenerationSuggestion(image: "BabyFly", title: "Baby Fly")
                        ImageGenerationSuggestion(image: "Motorcycle", title: "Motorcycle Boy")
                        ImageGenerationSuggestion(image: "Skiing", title: "Baby Skiing")
                        ImageGenerationSuggestion(image: "CartoonPortrait", title: "Playful Cartoon")
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
}

private struct ImageGenerationSuggestion: View {
    let image: String
    let title: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(image)
                .resizable()
                .scaledToFill()
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(8)
        }
        .frame(width: 86, height: 130)
        .clipped()
    }
}

private struct FixedAIImageFeature: View {
    @Binding var credits: Int
    @Environment(\.dismiss) private var dismiss
    @State private var mode: AIImageMode
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var prompt = ""
    @State private var selectedModel = AIImageModel.nanoBanana
    @State private var showModelMenu = false
    @State private var showSettings = false
    @State private var showCredits = false
    @State private var showDraftWarning = false
    @State private var showCropIndex: Int?
    @State private var resolution = "1k"
    @State private var ratio = "9:16"
    @State private var outputCount = "1"

    init(credits: Binding<Int>, initialMode: AIImageMode = .image) {
        _credits = credits
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        ZStack {
            FixedFeatureScaffold(
                title: "AI Image",
                showsHelp: false,
                onBack: requestDismiss
            ) {
                VStack(alignment: .leading, spacing: 22) {
                    FeatureModeTabs(
                        options: [("Image to Image", .image), ("Text to Image", .text)],
                        selection: $mode
                    )

                    if mode == .image {
                        Text("Image(\(selectedImages.count)/3)")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(AppPalette.brownInk)

                        ScrollView(.horizontal) {
                            PhotosPicker(selection: $selectedItems, maxSelectionCount: 3, matching: .images) {
                                HStack(spacing: 14) {
                                    ForEach(0..<3, id: \.self) { index in
                                        FeatureImageSlot(
                                            image: selectedImages.indices.contains(index) ? selectedImages[index] : nil,
                                            title: index == 0 ? nil : "Optional",
                                            onEdit: selectedImages.indices.contains(index) ? { showCropIndex = index } : nil
                                        )
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .scrollIndicators(.hidden)
                    }

                    ZStack(alignment: .bottom) {
                        FeaturePromptBox(
                            text: $prompt,
                            placeholder: mode == .image ? "Describe the content you want to create." : "Describe the image you want to create.Example: A puppy running on the grass.",
                            height: mode == .image ? 152 : 280
                        )

                        HStack {
                            if mode == .image {
                                Button { prompt.append(" @") } label: {
                                    Text("@")
                                        .font(.system(size: 19, weight: .bold))
                                        .foregroundStyle(AppPalette.surfaceEdge)
                                        .frame(width: 42, height: 42)
                                        .background(Color.white.opacity(0.40), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                Spacer(minLength: 0)
                                modelButton
                                Spacer(minLength: 0)
                                Color.clear.frame(width: 42, height: 42)
                            } else {
                                modelButton
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 9)
                        .zIndex(2)
                    }
                    .padding(.top, mode == .text ? 12 : 0)

                    FeatureSettingsSummary(values: ["\(outputCount) Img", resolution, ratio], onTap: { showSettings = true })
                }
            } footer: {
                FeaturePrimaryButton(
                    title: "Generate",
                    cost: mode == .image ? 30 : 28,
                    credits: $credits,
                    onNeedCredits: { showCredits = true },
                    onCreate: {}
                )
            }

            if showDraftWarning {
                FeatureDraftWarningOverlay(onConfirm: { dismiss() }, onCancel: { showDraftWarning = false })
                    .zIndex(2)
            }
        }
        .onChange(of: selectedItems) { _, items in loadImages(items) }
        .onChange(of: mode) { _, _ in showModelMenu = false }
        .sheet(isPresented: $showSettings) {
            AIImageOutputSettingsSheet(
                resolution: $resolution,
                ratio: $ratio,
                outputCount: $outputCount
            )
            .presentationDetents([.fraction(0.64)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(30)
        }
        .fullScreenCover(isPresented: $showCredits) { CreditCenterView(credits: $credits) }
        .fullScreenCover(
            isPresented: Binding(
                get: { showCropIndex != nil },
                set: { if !$0 { showCropIndex = nil } }
            )
        ) {
            if let index = showCropIndex, selectedImages.indices.contains(index) {
                FeaturePhotoCropView(image: selectedImages[index])
            }
        }
        .preferredColorScheme(.light)
    }

    private var modelButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { showModelMenu.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(selectedModel.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(selectedModel.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.16))
            .padding(.horizontal, 8)
            .frame(width: 146, height: 36)
            .background(.white.opacity(0.28), in: Capsule())
            .overlay(Capsule().stroke(Color(red: 1.0, green: 0.66, blue: 0.20), lineWidth: 1.1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai-image-model-picker")
        .overlay(alignment: .bottom) {
            if showModelMenu {
                AIImageModelMenu(selection: $selectedModel) {
                    showModelMenu = false
                }
                .offset(y: 8)
                .zIndex(4)
            }
        }
    }

    private func loadImages(_ items: [PhotosPickerItem]) {
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            await MainActor.run { selectedImages = images }
        }
    }

    private func requestDismiss() {
        if !selectedImages.isEmpty || !prompt.isEmpty { showDraftWarning = true } else { dismiss() }
    }
}

private enum AIImageMode: Hashable {
    case image
    case text
}

private enum AIImageModel: String, CaseIterable, Identifiable {
    case gptImage = "GPT Image 2"
    case kling = "Kling O1"
    case nanoBanana = "Nano Banana2"

    var id: String { rawValue }
    var title: String { rawValue }

    var assetName: String {
        switch self {
        case .gptImage: "GPTImageModelIcon"
        case .kling: "KlingModelIcon"
        case .nanoBanana: "NanoBananaModelIcon"
        }
    }
}

private struct AIImageModelMenu: View {
    @Binding var selection: AIImageModel
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(AIImageModel.allCases) { model in
                Button {
                    selection = model
                    onSelect()
                } label: {
                    HStack(spacing: 7) {
                        Image(model.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text(model.title)
                            .font(.system(size: 13.5, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.25))
                    .padding(.horizontal, 8)
                    .frame(width: 140, height: 44)
                    .background(selection == model ? Color(red: 1.0, green: 0.97, blue: 0.90) : .white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai-image-model-\(model.id)")
            }
        }
        .padding(3)
        .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color(red: 1.0, green: 0.66, blue: 0.20), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }
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
    let onEdit: (() -> Void)?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 10) {
                    FeatureAddPhotoIcon()
                        .frame(width: 34, height: 34)
                    if let title {
                        Text(title)
                            .font(.system(size: 18, weight: .medium))
                    }
                }
                .foregroundStyle(AppPalette.surfaceEdge)
            }

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "crop")
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .frame(width: 158, height: 218)
        .background(Color.white.opacity(0.40), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppPalette.surfaceEdge.opacity(0.75), lineWidth: 1.2))
    }
}

private struct FixedFusionFeature: View {
    @Binding var credits: Int
    @Environment(\.dismiss) private var dismiss
    @State private var hasStarted = false
    @State private var showPicker = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var prompt = ""
    @State private var showSettings = false
    @State private var showCredits = false
    @State private var showDraftWarning = false
    @State private var showCropIndex: Int?
    @State private var soundEnabled = false
    @State private var multiShotEnabled = false
    @State private var duration = "5s"
    @State private var resolution = "540p"
    @State private var ratio = "9:16"
    @State private var showGenerationFlow = false

    var body: some View {
        ZStack {
            if hasStarted {
                fusionEditor
            } else {
                fusionLanding
            }

            if showDraftWarning {
                FeatureDraftWarningOverlay(onConfirm: { dismiss() }, onCancel: { showDraftWarning = false })
                    .zIndex(4)
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $selectedItems, maxSelectionCount: 3, matching: .images)
        .onChange(of: selectedItems) { _, items in
            loadImages(items)
            if !items.isEmpty { hasStarted = true }
        }
        .sheet(isPresented: $showSettings) {
            FeatureSettingsSheet(
                mode: .video,
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
            VideoGenerationFlowView(
                title: "Fusion",
                templateTitle: "Generated Video",
                videoName: "baby_fly",
                template: nil,
                onRegenerate: { showGenerationFlow = false },
                onClose: { showGenerationFlow = false }
            )
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { showCropIndex != nil },
                set: { if !$0 { showCropIndex = nil } }
            )
        ) {
            if let index = showCropIndex, selectedImages.indices.contains(index) {
                FeaturePhotoCropView(image: selectedImages[index])
            }
        }
    }

    private var fusionLanding: some View {
        ZStack {
            Image("FusionReferenceScene")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Rectangle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: 96, height: 96)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    Spacer()
                }
                .padding(.top, 28)
                .padding(.horizontal, 8)

                Spacer()

                Button { showPicker = true } label: {
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(maxWidth: .infinity)
                        .frame(height: 92)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose Photo")
                .padding(.horizontal, 44)
                .padding(.bottom, 22)
            }

            Text("Fusion")
                .foregroundStyle(.clear)
                .accessibilityHidden(false)
        }
    }

    private var fusionEditor: some View {
        FixedFeatureScaffold(title: "Fusion", onBack: requestDismiss) {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal) {
                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 3, matching: .images) {
                        HStack(spacing: 14) {
                            ForEach(0..<3, id: \.self) { index in
                                FeatureImageSlot(
                                    image: selectedImages.indices.contains(index) ? selectedImages[index] : nil,
                                    title: index == 0 ? "Image\(index + 1)" : "Optional",
                                    onEdit: selectedImages.indices.contains(index) ? { showCropIndex = index } : nil
                                )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .scrollIndicators(.hidden)

                FeaturePromptBox(text: $prompt, placeholder: "Describe your video vision here")

                FeatureSettingsSummary(
                    values: [soundEnabled ? "sound" : "mute", multiShotEnabled ? "multi" : "single", duration, resolution, ratio],
                    onTap: { showSettings = true }
                )

                Text("Creative Exploration")
                    .font(.system(size: 23, weight: .heavy))
                    .foregroundStyle(AppPalette.ink)

                ScrollView(.horizontal) {
                    HStack(spacing: 13) {
                        FeatureExploreCard(image: "Cowboy", title: "Horse")
                        FeatureExploreCard(image: "BabyFly", title: "Happy Puppy")
                        FeatureExploreCard(image: "Skiing", title: "Dragon & Volcano")
                    }
                }
                .scrollIndicators(.hidden)
            }
        } footer: {
            FeaturePrimaryButton(
                title: "Generate",
                cost: 40,
                credits: $credits,
                onNeedCredits: { showCredits = true },
                onCreate: { showGenerationFlow = true }
            )
        }
    }

    private func loadImages(_ items: [PhotosPickerItem]) {
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) }
            }
            await MainActor.run { selectedImages = images }
        }
    }

    private func requestDismiss() {
        if !selectedImages.isEmpty || !prompt.isEmpty { showDraftWarning = true } else { dismiss() }
    }
}

private struct FeatureExploreCard: View {
    let image: String
    let title: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(image)
                .resizable()
                .scaledToFill()
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .padding(10)
        }
        .frame(width: 145, height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct AIImageOutputSettingsSheet: View {
    @Binding var resolution: String
    @Binding var ratio: String
    @Binding var outputCount: String
    @Environment(\.dismiss) private var dismiss

    private let ratios = ["16:9", "9:16", "1:1", "4:3", "3:4", "3:2", "2:3", "21:9"]
    private let selectionColor = Color(red: 0.86, green: 0.30, blue: 0.22)
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingSection("Resolution") {
                singleChoiceGrid("1k", selection: $resolution)
            }

            settingSection("Ratio") {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(ratios, id: \.self) { value in
                        singleChoice(value, selection: $ratio)
                    }
                }
            }

            settingSection("Output Image Number") {
                singleChoiceGrid("1", selection: $outputCount)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 63)
        .padding(.bottom, 18)
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
    }

    private func settingSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.14))
            content()
        }
    }

    private func singleChoiceGrid(_ value: String, selection: Binding<String>) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            singleChoice(value, selection: selection)
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
    @Binding var soundEnabled: Bool
    @Binding var multiShotEnabled: Bool
    @Binding var duration: String
    @Binding var resolution: String
    @Binding var ratio: String
    @Binding var outputCount: String
    @Environment(\.dismiss) private var dismiss

    private let ratios = ["16:9", "9:16", "1:1", "4:3", "3:4", "3:2", "2:3", "21:9"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mode == .video {
                        settingToggle("Sounds", off: "speaker.slash.fill", on: "speaker.wave.2.fill", value: $soundEnabled)
                        settingToggle("Multi-Shot Video", off: "video.slash.fill", on: "video.badge.waveform.fill", value: $multiShotEnabled)
                        settingGrid("Duration", values: ["5s", "8s", "10s"], selection: $duration)
                        settingGrid("Resolution", values: ["540p", "720p", "1080p"], selection: $resolution)
                        settingGrid("Ratio", values: ["16:9", "1:1", "9:16", "4:3", "3:4"], selection: $ratio)
                    } else {
                        settingGrid("Resolution", values: ["1k"], selection: $resolution)
                        settingGrid("Ratio", values: ratios, selection: $ratio)
                        settingGrid("Output Image Number", values: ["1", "2", "4"], selection: $outputCount)
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
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var ratio = "FREEFORM"

    private let ratios = ["ORIGINAL", "FREEFORM", "1:1", "1:2", "2:1", "3:4", "4:3"]

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.06).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 30)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .overlay(Rectangle().stroke(.white, lineWidth: 2))
                    .padding(.horizontal, 14)

                HStack(spacing: 27) {
                    Image(systemName: "rotate.left")
                    Image(systemName: "triangle.lefthalf.filled")
                    Spacer()
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.gray)
                }
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white)
                .padding(.horizontal, 44)
                .padding(.top, 30)

                ScrollView(.horizontal) {
                    HStack(spacing: 18) {
                        ForEach(ratios, id: \.self) { value in
                            Button { ratio = value } label: {
                                Text(value)
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(ratio == value ? .white : .gray)
                                    .padding(.horizontal, ratio == value ? 16 : 0)
                                    .frame(height: 44)
                                    .background(ratio == value ? Color.gray.opacity(0.75) : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
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

                    Button { dismiss() } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 104, height: 58)
                            .background(AppPalette.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
                .padding(.top, 38)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }
}
