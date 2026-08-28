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
    let imageURL: URL
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                ConfiguredPromotionImage(url: imageURL)
                    .aspectRatio(3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TemplatePressStyle())
            .accessibilityIdentifier("home-discount-banner")

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

struct MePage: View {
    @ObservedObject var accountStore: AppAccountStore
    let onCreate: (FixedFeature) -> Void
    let onSettings: () -> Void
    @State private var kind = "Video"
    @State private var showNotice = false
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var selectedHistoryTask: GenerationHistoryTask?
    @State private var deletingTaskID: String?

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
        accountStore.historyTasks.filter { kind == "Video" ? $0.isVideo : !$0.isVideo }
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
            LazyVStack(spacing: 16) {
                ForEach(visibleHistoryTasks) { task in
                    MeHistoryTaskCard(
                        task: task,
                        isDeleting: deletingTaskID == task.id,
                        onOpen: { selectedHistoryTask = task },
                        onDelete: { deleteHistoryTask(task) }
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
                presentNotice(title: "Delete Failed", message: error.localizedDescription)
            }
        }
    }
}

private struct MeHistoryTaskCard: View {
    let task: GenerationHistoryTask
    let isDeleting: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.scene?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Creation")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppPalette.brownInk)
                    Text(task.createdAt.photoReviveDisplayDate)
                        .font(.caption)
                        .foregroundStyle(AppPalette.brownInk.opacity(0.65))
                }

                Spacer()

                Text(task.status.capitalized)
                    .font(.caption.bold())
                    .foregroundStyle(task.status == "completed" ? Color.green : AppPalette.orange)

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

            Button(action: onOpen) {
                ZStack {
                    Color.black.opacity(0.90)
                    if task.resultURL != nil, task.status == "completed" {
                        if let coverURL = task.coverURL {
                            CachedRemoteImage(url: coverURL) { image in
                                Image(uiImage: image).resizable().scaledToFill()
                            } placeholder: {
                                ProgressView().tint(.white)
                            } failure: {
                                Image(systemName: "photo").foregroundStyle(.white.opacity(0.72))
                            }
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: task.isVideo ? "play.rectangle.fill" : "photo")
                                    .font(.system(size: 36))
                                Text(task.isVideo ? "Tap to play" : "Open result")
                                    .font(.caption)
                            }
                            .foregroundStyle(.white.opacity(0.82))
                        }
                    } else {
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text(task.errorMessage ?? "Generation \(task.status)")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }

                    if task.coverURL != nil, task.status == "completed" {
                        GeneratedContentWatermark()
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(task.resultURL == nil)

            if let creditsUsed = task.creditsUsed {
                Label("\(creditsUsed) credits", systemImage: "diamond.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.orange)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.74), lineWidth: 1))
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
                    RemoteLoopingVideoView(url: url, videoGravity: .resizeAspect)
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
            .padding(18)
        }
        .preferredColorScheme(.dark)
    }
}
