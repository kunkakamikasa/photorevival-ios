import Combine
import Foundation

@MainActor
final class FeatureConfigStore: ObservableObject {
    @Published private(set) var videoSections: [TemplateSection] = []
    @Published private(set) var isLoading = false

    private static let appID = "photorevival"
    private static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxyZW5sZ3FwcHZxZmJpYnhwcGJpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI1MTIxODMsImV4cCI6MjA3ODA4ODE4M30.xVbKv4Es1sZRtWYsqbcu4eBoL1XZlMcyLcEJTTpddP4"

    var heroItems: [TemplateItem] {
        Array(videoSections.flatMap(\.items).prefix(3))
    }

    func detailItems(for item: TemplateItem) -> [TemplateItem] {
        guard let groupID = item.detailGroupID,
              let section = videoSections.first(where: { $0.id == groupID }) else {
            return [item]
        }
        return section.items
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var components = URLComponents(
                string: "https://lrenlgqppvqfbibxppbi.supabase.co/functions/v1/get-feature-configs"
            )
            components?.queryItems = [
                URLQueryItem(name: "app_id", value: Self.appID),
                URLQueryItem(name: "menu", value: "video"),
                URLQueryItem(name: "page_type", value: "default"),
                URLQueryItem(name: "limit", value: "20")
            ]
            guard let url = components?.url else { return }

            var request = URLRequest(url: url)
            request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(Self.anonKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                return
            }

            let payload = try JSONDecoder().decode(FeatureConfigResponse.self, from: data)
            videoSections = payload.sections.compactMap(\.templateSection)
        } catch {
            // An empty catalog is intentional: do not restore placeholder covers on failure.
        }
    }
}

private struct FeatureConfigResponse: Decodable {
    let sections: [RemoteFeatureSection]
}

private struct RemoteFeatureSection: Decodable {
    let id: Int
    let title: String?
    let items: [RemoteFeatureItem]

    var templateSection: TemplateSection? {
        guard let title, !title.isEmpty else { return nil }
        let groupID = "cms-section-\(id)"
        let mappedItems = items.compactMap { $0.templateItem(groupID: groupID) }
        guard !mappedItems.isEmpty else { return nil }
        return TemplateSection(title, id: groupID, items: mappedItems, generationKind: .video)
    }
}

private struct RemoteFeatureItem: Decodable {
    let id: String
    let title: String
    let badge: String?
    let promptTemplate: String?
    let estimatedCredits: Int
    let modelType: String?
    let modelID: String?
    let coverVideo: String?
    let coverVideoThumbnail: String?
    let materialRequirements: [RemoteMaterialRequirement]

    enum CodingKeys: String, CodingKey {
        case id, title, badge
        case promptTemplate = "prompt_template"
        case estimatedCredits = "estimated_credits"
        case modelType = "model_type"
        case modelID = "model_id"
        case coverVideo = "cover_video"
        case coverVideoThumbnail = "cover_video_thumbnail"
        case materialRequirements = "material_requirements"
    }

    func templateItem(groupID: String) -> TemplateItem? {
        guard let coverVideo,
              let coverVideoURL = URL(string: coverVideo),
              let coverVideoThumbnail,
              let coverImageURL = URL(string: coverVideoThumbnail) else {
            return nil
        }

        let referenceCount = materialRequirements.reduce(0) { count, requirement in
            switch requirement.type {
            case "single_image": count + 1
            case "multiple_images": count + (requirement.imageCount ?? 1)
            default: count
            }
        }

        return TemplateItem(
            id: id,
            title: title,
            coverImageURL: coverImageURL,
            coverVideoURL: coverVideoURL,
            badge: badge,
            generationKind: .video,
            imageReferenceCount: max(1, referenceCount),
            detailGroupID: groupID,
            promptTemplate: promptTemplate,
            estimatedCredits: estimatedCredits,
            modelType: modelType,
            modelID: modelID
        )
    }
}

private struct RemoteMaterialRequirement: Decodable {
    let type: String
    let imageCount: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case imageCount = "image_count"
    }
}
