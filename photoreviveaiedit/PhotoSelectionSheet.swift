import CryptoKit
import PhotosUI
import SwiftUI
import UIKit

struct UploadedPhotoRecord: Identifiable, Hashable, Sendable {
    let id: String
    let fileURL: URL
    let modifiedAt: Date
}

/// Keeps a small, app-owned library of photos the user previously chose. The
/// cached copy is large enough to reuse as generation input without retaining
/// an unbounded collection of full-resolution camera originals.
actor UploadedPhotoLibrary {
    static let shared = UploadedPhotoLibrary()

    private let maximumPhotoCount = 30

    func records() -> [UploadedPhotoRecord] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: libraryDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return UploadedPhotoRecord(
                id: url.deletingPathExtension().lastPathComponent,
                fileURL: url,
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func savePhoto(data: Data) {
        guard let image = TemplateImageDecoder.image(from: data, maxPixelSize: 2_048),
              let jpegData = image.jpegData(compressionQuality: 0.92) else { return }

        let identifier = SHA256.hash(data: jpegData)
            .map { String(format: "%02x", $0) }
            .joined()
        let destination = libraryDirectory
            .appendingPathComponent(identifier)
            .appendingPathExtension("jpg")

        do {
            try FileManager.default.createDirectory(
                at: libraryDirectory,
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: destination.path) {
                try jpegData.write(to: destination, options: .atomic)
            }
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: destination.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDestination = destination
            try? mutableDestination.setResourceValues(values)
            trimIfNeeded()
        } catch {
            // Reusing a photo in the current flow must still work if its
            // optional history cache cannot be written.
        }
    }

    func image(
        for record: UploadedPhotoRecord,
        maxPixelSize: Int = 2_048
    ) -> UIImage? {
        guard let data = try? Data(contentsOf: record.fileURL, options: .mappedIfSafe) else {
            return nil
        }
        return TemplateImageDecoder.image(from: data, maxPixelSize: maxPixelSize)
    }

    private var libraryDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PreviouslyUploadedPhotos", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    private func trimIfNeeded() {
        let allRecords = records()
        guard allRecords.count > maximumPhotoCount else { return }
        for record in allRecords.dropFirst(maximumPhotoCount) {
            try? FileManager.default.removeItem(at: record.fileURL)
        }
    }
}

enum PhotoSelectionLibrary {
    static func createdPhotoTasks(from tasks: [GenerationHistoryTask]) -> [GenerationHistoryTask] {
        tasks.filter {
            $0.status.lowercased() == "completed"
                && !$0.isVideo
                && $0.resultURL != nil
        }
    }
}

struct PhotoSelectionSheet: View {
    private enum LibraryTab: String, CaseIterable, Identifiable {
        case uploaded = "Uploaded"
        case created = "Created"

        var id: String { rawValue }
        var displayTitle: String {
            switch self {
            case .uploaded: AppLocalization.string("Uploaded")
            case .created: AppLocalization.string("Created")
            }
        }
    }

    let maximumSelectionCount: Int
    let onSelect: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var accountStore: AppAccountStore
    @State private var selectedTab = LibraryTab.uploaded
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploadedPhotos: [UploadedPhotoRecord] = []
    @State private var loadingPhotoID: String?
    @State private var selectionError: String?

    init(
        maximumSelectionCount: Int = 1,
        accountStore: AppAccountStore? = nil,
        onSelect: @escaping ([UIImage]) -> Void
    ) {
        self.maximumSelectionCount = max(1, maximumSelectionCount)
        self.onSelect = onSelect
        _accountStore = ObservedObject(wrappedValue: accountStore ?? .shared)
    }

    private var createdPhotos: [GenerationHistoryTask] {
        PhotoSelectionLibrary.createdPhotoTasks(from: accountStore.historyTasks)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)

            tabPicker
                .padding(.horizontal, 20)
                .padding(.top, 20)

            photoGrid
                .padding(.top, 14)
        }
        .background(Color.white)
        .accessibilityIdentifier("photo-selection-sheet")
        .task {
            uploadedPhotos = await UploadedPhotoLibrary.shared.records()
            if accountStore.isAuthenticated {
                await accountStore.refreshHistory()
            }
        }
        .onChange(of: pickerItems) { _, items in
            loadPhotosPickerItems(items)
        }
        .alert(
            "Photo unavailable",
            isPresented: Binding(
                get: { selectionError != nil },
                set: { if !$0 { selectionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { selectionError = nil }
        } message: {
            Text(selectionError ?? "Please choose another photo.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Choose Photo")
                .font(.system(size: 29, weight: .heavy))
                .foregroundStyle(AppPalette.ink)

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close photo chooser")
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(LibraryTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.displayTitle)
                        .font(.system(size: 18, weight: selectedTab == tab ? .bold : .medium))
                        .foregroundStyle(selectedTab == tab ? AppPalette.ink : AppPalette.brownInk.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color(red: 1.00, green: 0.78, blue: 0.40))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                .accessibilityIdentifier("photo-selection-tab-\(tab.rawValue.lowercased())")
            }
        }
        .padding(2)
        .background(
            Color(red: 1.00, green: 0.96, blue: 0.88),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
    }

    private var photoGrid: some View {
        ScrollView {
            if selectedTab == .uploaded {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: maximumSelectionCount,
                        matching: .images
                    ) {
                        ChooseFromPhotosTile()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("photo-selection-choose-from-photos")

                    ForEach(uploadedPhotos) { record in
                        Button {
                            selectUploadedPhoto(record)
                        } label: {
                            UploadedPhotoTile(record: record)
                                .overlay {
                                    if loadingPhotoID == record.id {
                                        PhotoSelectionLoadingOverlay()
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use previously uploaded photo")
                        .accessibilityIdentifier("photo-selection-uploaded-\(record.id)")
                    }
                }
            } else if createdPhotos.isEmpty {
                createdEmptyState
                    .frame(maxWidth: .infinity)
                    .padding(.top, 54)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(createdPhotos) { task in
                        if let resultURL = task.resultURL {
                            Button {
                                selectCreatedPhoto(task)
                            } label: {
                                CreatedPhotoTile(url: resultURL)
                                    .overlay {
                                        if loadingPhotoID == task.id {
                                            PhotoSelectionLoadingOverlay()
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use a photo created with Photo Revival")
                            .accessibilityIdentifier("photo-selection-created-\(task.id)")
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
    }

    private var createdEmptyState: some View {
        VStack(spacing: 12) {
            if accountStore.isLoadingHistory {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(AppPalette.surfaceEdge)

                Text(accountStore.isAuthenticated ? "No created photos yet" : "Sign in to view created photos")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppPalette.brownInk)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: 0, maximum: .infinity),
                spacing: 10
            ),
            count: 3
        )
    }

    private func loadPhotosPickerItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, loadingPhotoID == nil else { return }
        loadingPhotoID = "system-library"

        Task {
            var images: [UIImage] = []
            for item in items.prefix(maximumSelectionCount) {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                images.append(image)
                await UploadedPhotoLibrary.shared.savePhoto(data: data)
            }

            loadingPhotoID = nil
            guard !images.isEmpty else {
                selectionError = "The selected photo could not be loaded. Please choose another one."
                pickerItems = []
                return
            }
            onSelect(images)
            dismiss()
        }
    }

    private func selectUploadedPhoto(_ record: UploadedPhotoRecord) {
        guard loadingPhotoID == nil else { return }
        loadingPhotoID = record.id
        Task {
            let image = await UploadedPhotoLibrary.shared.image(for: record)
            loadingPhotoID = nil
            guard let image else {
                selectionError = "This previously uploaded photo is no longer available."
                uploadedPhotos = await UploadedPhotoLibrary.shared.records()
                return
            }
            onSelect([image])
            dismiss()
        }
    }

    private func selectCreatedPhoto(_ task: GenerationHistoryTask) {
        guard loadingPhotoID == nil, let resultURL = task.resultURL else { return }
        loadingPhotoID = task.id
        Task {
            do {
                let image = try await TemplateImageRepository.shared.image(
                    for: resultURL,
                    maxPixelSize: 2_048
                )
                loadingPhotoID = nil
                onSelect([image])
                dismiss()
            } catch {
                loadingPhotoID = nil
                selectionError = "This created photo could not be loaded. Please try again."
            }
        }
    }
}

private struct ChooseFromPhotosTile: View {
    var body: some View {
        PhotoSelectionTile {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 31, weight: .medium))

                Text("Choose\nfrom Photos")
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color(.systemGray2))
        }
    }
}

private struct UploadedPhotoTile: View {
    let record: UploadedPhotoRecord
    @State private var image: UIImage?

    var body: some View {
        PhotoSelectionTile {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .tint(AppPalette.surfaceEdge)
            }
        }
        .task(id: record.id) {
            image = await UploadedPhotoLibrary.shared.image(
                for: record,
                maxPixelSize: 480
            )
        }
    }
}

private struct CreatedPhotoTile: View {
    let url: URL

    var body: some View {
        PhotoSelectionTile {
            CachedRemoteImage(url: url) { image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView().tint(AppPalette.surfaceEdge)
            } failure: {
                Image(systemName: "photo")
                    .foregroundStyle(AppPalette.surfaceEdge)
            }
        }
    }
}

/// The neutral background owns the tile's size. Image content is placed in an
/// overlay so tall or wide source photos cannot change a grid row's height.
private struct PhotoSelectionTile<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Color(.systemGray6)
            .aspectRatio(0.75, contentMode: .fit)
            .overlay {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PhotoSelectionLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
