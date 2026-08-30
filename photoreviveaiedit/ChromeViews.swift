import AVFoundation
import SwiftUI
import UIKit

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
    let imageURL: URL
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FixedAspectRatioLayout(aspectRatio: 3.0) {
                Button(action: onOpen) {
                    ConfiguredPromotionImage(
                        url: imageURL,
                        contentMode: .scaleAspectFit
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TemplatePressStyle())
                .accessibilityIdentifier("home-discount-banner")
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
        .clipped()
    }
}

private struct FixedAspectRatioLayout: Layout {
    let aspectRatio: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = max(proposal.width ?? 0, 0)
        return CGSize(width: width, height: width / aspectRatio)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let childProposal = ProposedViewSize(width: bounds.width, height: bounds.height)
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY),
                anchor: .center,
                proposal: childProposal
            )
        }
    }
}

struct MePage: View {
    @ObservedObject var accountStore: AppAccountStore
    let onCreate: (FixedFeature) -> Void
    let onSettings: () -> Void
    @State private var kind = "Video"
    @State private var showNotice = false
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var selectedHistoryTask: GenerationHistoryTask?
    @State private var taskPendingDeletion: GenerationHistoryTask?
    @State private var deletingTaskID: String?
    @State private var exportingTaskID: String?
    @State private var activeShareSheet: MeHistoryShareSheet?
    @State private var showPaywall = false
    @AppStorage("isSubscribed") private var isSubscribed = false

    init(
        accountStore: AppAccountStore? = nil,
        onCreate: @escaping (FixedFeature) -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.accountStore = accountStore ?? .shared
        self.onCreate = onCreate
        self.onSettings = onSettings
    }

    private var visibleHistoryTasks: [GenerationHistoryTask] {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showHistoryResultPreview"),
           let previewURL = Bundle.main.url(
               forResource: "OnboardingRestoreVideo",
               withExtension: "mp4"
           ) {
            return [
                GenerationHistoryTask(
                    id: "history-result-preview",
                    scene: "revive_old_photos",
                    status: "completed",
                    outputURL: previewURL.absoluteString,
                    convertedURL: nil,
                    thumbnailURL: nil,
                    thumbnailSource: nil,
                    creditsUsed: 20,
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    contentType: "video",
                    sectionMenu: "memory",
                    errorMessage: nil
                )
            ]
        }
#endif
        return accountStore.historyTasks.filter { kind == "Video" ? $0.isVideo : !$0.isVideo }
    }

    var body: some View {
        VStack(spacing: 0) {
            meHeader

            if !visibleHistoryTasks.isEmpty {
                historyContent
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
        .fullScreenCover(item: $selectedHistoryTask) { task in
            MeHistoryPreviewView(task: task) {
                selectedHistoryTask = nil
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallOfferFlowView(analyticsSource: "history_remove_watermark")
        }
        .sheet(item: $activeShareSheet) { sheet in
            switch sheet {
            case .activity(let url):
                GeneratedMediaActivityView(activityItems: [url])
            case .messages(let url):
                GeneratedMessageComposeView(attachmentURL: url) {
                    activeShareSheet = nil
                }
            }
        }
        .alert(
            "Permanently delete this creation?",
            isPresented: Binding(
                get: { taskPendingDeletion != nil },
                set: { if !$0 { taskPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                taskPendingDeletion = nil
            }
            Button("Delete Permanently", role: .destructive) {
                guard let task = taskPendingDeletion else { return }
                taskPendingDeletion = nil
                deleteHistoryTask(task)
            }
        } message: {
            Text("This creation will be permanently deleted and cannot be recovered.")
        }
        .alert(noticeTitle, isPresented: $showNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
        .task {
            await accountStore.refreshHistory()
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

    private var historyContent: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                ForEach(visibleHistoryTasks) { task in
                    MeHistoryTaskCard(
                        task: task,
                        isDeleting: deletingTaskID == task.id,
                        isExporting: exportingTaskID == task.id,
                        isSubscribed: isSubscribed,
                        onOpen: { selectedHistoryTask = task },
                        onSave: { saveHistoryTask(task) },
                        onShare: { shareHistoryTask(task) },
                        onShareTo: { destination in
                            shareHistoryTask(task, to: destination)
                        },
                        onRemoveWatermark: { showPaywall = true },
                        onDelete: { taskPendingDeletion = task }
                    )
                }

                if accountStore.hasMoreHistory {
                    Button {
                        Task { await accountStore.loadMoreHistory() }
                    } label: {
                        if accountStore.isLoadingMoreHistory {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Load More")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(accountStore.isLoadingMoreHistory)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
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
                onCreate(kind == "Video" ? .photoToVideo : .imageToImage)
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

    private func deleteHistoryTask(_ task: GenerationHistoryTask) {
        guard deletingTaskID == nil else { return }
        deletingTaskID = task.id
        Task {
            defer { deletingTaskID = nil }
            do {
                try await accountStore.deleteHistoryTask(id: task.id)
            } catch {
                presentNotice(
                    title: "Delete Failed",
                    message: error.userFacingEnglishMessage(
                        fallback: "The creation could not be deleted. Please try again."
                    )
                )
            }
        }
    }

    private func saveHistoryTask(_ task: GenerationHistoryTask) {
        guard exportingTaskID == nil else { return }
        exportingTaskID = task.id
        Task {
            defer { exportingTaskID = nil }
            do {
                let fileURL = try await prepareHistoryMedia(task)
                if task.isVideo {
                    try await GeneratedMediaExporter.saveVideo(at: fileURL)
                } else {
                    try await GeneratedMediaExporter.saveImage(at: fileURL)
                }
                AppAnalytics.contentSaved(
                    contentType: task.isVideo ? "video" : "image",
                    itemID: task.scene
                )
                presentNotice(title: "Saved", message: "This creation was saved to Photos.")
            } catch {
                presentNotice(
                    title: "Save Failed",
                    message: error.userFacingEnglishMessage(
                        fallback: "The creation could not be saved. Please try again."
                    )
                )
            }
        }
    }

    private func shareHistoryTask(
        _ task: GenerationHistoryTask
    ) {
        guard exportingTaskID == nil else { return }
        exportingTaskID = task.id
        Task {
            defer { exportingTaskID = nil }
            do {
                activeShareSheet = .activity(try await prepareHistoryMedia(task))
            } catch {
                presentNotice(
                    title: "Share Failed",
                    message: error.userFacingEnglishMessage(
                        fallback: "The creation could not be shared. Please try again."
                    )
                )
            }
        }
    }

    private func shareHistoryTask(
        _ task: GenerationHistoryTask,
        to destination: GeneratedSocialShareDestination
    ) {
        guard exportingTaskID == nil else { return }
        exportingTaskID = task.id
        Task {
            defer { exportingTaskID = nil }
            do {
                switch destination {
                case .messages:
                    let fileURL = try await prepareHistoryMedia(task)
                    activeShareSheet = GeneratedMessageComposeView.canSendAttachment
                        ? .messages(fileURL)
                        : .activity(fileURL)

                case .whatsApp:
                    if let resultURL = task.resultURL,
                       let url = GeneratedSocialShareRouter.whatsAppURL(for: resultURL),
                       await openExternalShareURL(url) {
                        return
                    }
                    activeShareSheet = .activity(try await prepareHistoryMedia(task))

                case .facebook:
                    if let resultURL = task.resultURL,
                       let url = GeneratedSocialShareRouter.facebookURL(for: resultURL),
                       await openExternalShareURL(url) {
                        return
                    }
                    activeShareSheet = .activity(try await prepareHistoryMedia(task))

                case .instagram:
                    let fileURL = try await prepareHistoryMedia(task)
                    let url = try await GeneratedSocialShareRouter.stageInstagramStory(
                        mediaURL: fileURL,
                        isVideo: task.isVideo
                    )
                    if await openExternalShareURL(url) {
                        return
                    }
                    activeShareSheet = .activity(fileURL)
                }
            } catch {
                presentNotice(
                    title: "Share Failed",
                    message: error.userFacingEnglishMessage(
                        fallback: "The creation could not be shared. Please try again."
                    )
                )
            }
        }
    }

    private func openExternalShareURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }

    private func prepareHistoryMedia(_ task: GenerationHistoryTask) async throws -> URL {
        guard let resultURL = task.resultURL else {
            throw GeneratedMediaExportError.mediaUnavailable
        }
        if task.isVideo {
            return try await GeneratedMediaExporter.prepareVideo(
                from: resultURL,
                addsWatermark: !isSubscribed
            )
        }

        let image = try await loadHistoryImage(from: resultURL)
        return try GeneratedMediaExporter.prepareImage(
            image,
            addsWatermark: !isSubscribed
        )
    }

    private func loadHistoryImage(from url: URL) async throws -> UIImage {
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (downloadedData, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw GeneratedMediaExportError.mediaUnavailable
            }
            data = downloadedData
        }
        guard let image = UIImage(data: data) else {
            throw GeneratedMediaExportError.mediaUnavailable
        }
        return image
    }
}

private struct MeHistoryTaskCard: View {
    let task: GenerationHistoryTask
    let isDeleting: Bool
    let isExporting: Bool
    let isSubscribed: Bool
    let onOpen: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onShareTo: (GeneratedSocialShareDestination) -> Void
    let onRemoveWatermark: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(historyTitle)
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(historySubtitle)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppPalette.brownInk)
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: 10)

                Text(historyDayText)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppPalette.brownInk)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Button(action: onDelete) {
                    Image(systemName: isDeleting ? "hourglass" : "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppPalette.accent)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .accessibilityLabel("Delete generation")
            }

            FixedAspectRatioLayout(aspectRatio: 16.0 / 9.0) {
                ZStack {
                    Color.black

                    if resultAvailable, let resultURL = task.resultURL {
                        historyMedia(url: resultURL)
                    } else {
                        VStack(spacing: 10) {
                            if task.status.lowercased() == "failed" {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 30))
                            } else {
                                ProgressView().tint(.white)
                            }
                            Text(task.userFacingErrorMessage)
                                .font(.subheadline)
                        }
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding()
                    }

                    if resultAvailable {
                        GeneratedContentWatermark()
                            .allowsHitTesting(false)

                        Button(action: onOpen) {
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
                        .accessibilityLabel("Maximize creation")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(.top, 18)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("history-result-media")

            if resultAvailable {
                if task.isVideo {
                    videoActionBar
                } else {
                    actionBar
                    sharePanel
                        .padding(.top, 4)
                }
            }
        }
        .accessibilityIdentifier("history-result-card-\(task.id)")
    }

    private var historyTitle: String {
        task.scene?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized ?? (task.isVideo ? "Generated Video" : "Generated Photo")
    }

    private var historySubtitle: String {
        if task.status.lowercased() != "completed" {
            return task.status.capitalized
        }
        if let section = task.sectionMenu?.lowercased(),
           !["video", "photo", "image"].contains(section) {
            return section.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return task.isVideo ? "AI Video" : "AI Photo"
    }

    private var historyDayText: String {
        let preciseFormatter = ISO8601DateFormatter()
        preciseFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = preciseFormatter.date(from: task.createdAt)
                ?? ISO8601DateFormatter().date(from: task.createdAt) else {
            return task.createdAt
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let shortFormatter = DateFormatter()
        shortFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        return shortFormatter.string(from: date)
    }

    private var resultAvailable: Bool {
        task.status.lowercased() == "completed" && task.resultURL != nil
    }

    @ViewBuilder
    private func historyMedia(url: URL) -> some View {
        if task.isVideo {
            GeneratedVideoPlayerView(
                url: url,
                videoGravity: .resizeAspect,
                autoplay: false
            )
            .accessibilityIdentifier("history-inline-video-player")
        } else {
            CachedRemoteImage(url: url) { image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ProgressView().tint(.white)
            } failure: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            Button(action: onSave) {
                Label(isExporting ? "Preparing…" : "Save", systemImage: "arrow.down.to.line")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .accessibilityLabel(task.isVideo ? "Save generated video" : "Save generated photo")

            if !isSubscribed {
                Divider()

                Button(action: onRemoveWatermark) {
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
    }

    private var videoActionBar: some View {
        HStack(spacing: 0) {
            Button(action: onSave) {
                Label(isExporting ? "Preparing…" : "Save", systemImage: "arrow.down.to.line")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .accessibilityLabel("Save generated video")

            Divider()

            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .accessibilityLabel("Share generated video")
        }
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.72), lineWidth: 1))
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

    private func shareButtonRow(iconSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            MeHistoryShareIcon(symbol: "bubble.left.and.bubble.right.fill", color: Color(red: 0.11, green: 0.81, blue: 0.25), label: "Messages", size: iconSize) {
                onShareTo(.messages)
            }
                .frame(maxWidth: .infinity)
            MeHistoryShareIcon(symbol: "message.fill", color: Color(red: 0.08, green: 0.78, blue: 0.27), label: "WhatsApp", size: iconSize) {
                onShareTo(.whatsApp)
            }
                .frame(maxWidth: .infinity)
            MeHistoryShareIcon(symbol: "f.cursive", color: Color(red: 0.06, green: 0.37, blue: 0.95), label: "Facebook", size: iconSize) {
                onShareTo(.facebook)
            }
                .frame(maxWidth: .infinity)
            MeHistoryShareIcon(symbol: "camera.fill", color: Color(red: 0.90, green: 0.15, blue: 0.54), label: "Instagram", size: iconSize) {
                onShareTo(.instagram)
            }
                .frame(maxWidth: .infinity)
        }
    }
}

private enum MeHistoryShareSheet: Identifiable {
    case activity(URL)
    case messages(URL)

    var id: String {
        switch self {
        case .activity(let url):
            "activity-\(url.absoluteString)"
        case .messages(let url):
            "messages-\(url.absoluteString)"
        }
    }
}

private struct MeHistoryShareIcon: View {
    let symbol: String
    let color: Color
    let label: String
    let size: CGFloat
    let action: () -> Void

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

private struct MeHistoryPreviewView: View {
    let task: GenerationHistoryTask
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = task.resultURL {
                if task.isVideo {
                    GeneratedVideoPlayerView(
                        url: url,
                        videoGravity: .resizeAspect,
                        autoplay: true
                    )
                    .accessibilityIdentifier("history-video-player")
                    .ignoresSafeArea(edges: .horizontal)
                } else {
                    CachedRemoteImage(url: url) { image in
                        Image(uiImage: image).resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    } failure: {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.white)
                    }
                    .padding()
                }
            }

            GeneratedContentWatermark()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.52), in: Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 18)
            .padding(.top, 44)
            .accessibilityLabel("Close preview")
        }
        .preferredColorScheme(.dark)
    }
}
