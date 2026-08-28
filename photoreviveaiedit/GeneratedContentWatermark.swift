import SwiftUI

enum PhotoRevivalBrand {
    static let fallbackFullName = "Photo Revival"

    static var fullName: String {
        guard let displayName = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String else {
            return fallbackFullName
        }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? fallbackFullName : trimmedName
    }
}

enum GeneratedContentWatermarkPolicy {
    static func isVisible(isSubscribed: Bool) -> Bool {
        !isSubscribed
    }
}

enum GeneratedContentWatermarkLayout {
    static func placements(in size: CGSize) -> [CGPoint] {
        guard size.width > 0, size.height > 0 else { return [] }

        let horizontalSpacing = min(max(size.width * 0.34, 92), 180)
        let verticalSpacing = min(max(size.height * 0.18, 66), 126)
        let columnCount = Int(ceil(size.width / horizontalSpacing)) + 2
        let rowCount = Int(ceil(size.height / verticalSpacing)) + 1

        return (0..<rowCount).flatMap { row in
            let stagger = row.isMultiple(of: 2) ? 0 : horizontalSpacing / 2
            return (0..<columnCount).map { column in
                CGPoint(
                    x: (-horizontalSpacing / 2) + CGFloat(column) * horizontalSpacing + stagger,
                    y: (verticalSpacing / 2) + CGFloat(row) * verticalSpacing
                )
            }
        }
    }
}

/// A light, repeated brand mark shared by generated images and videos.
/// Keeping subscription handling inside this view prevents a new result screen
/// from accidentally watermarking paying users.
struct GeneratedContentWatermark: View {
    @AppStorage("isSubscribed") private var isSubscribed = false

    var body: some View {
        if GeneratedContentWatermarkPolicy.isVisible(isSubscribed: isSubscribed) {
            GeometryReader { proxy in
                let fontSize = min(
                    max(min(proxy.size.width, proxy.size.height) * 0.04, 9),
                    16
                )
                let placements = GeneratedContentWatermarkLayout.placements(in: proxy.size)

                ForEach(Array(placements.enumerated()), id: \.offset) { _, placement in
                    Text(PhotoRevivalBrand.fullName)
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.26))
                        .shadow(color: .black.opacity(0.30), radius: 1)
                        .rotationEffect(.degrees(-20))
                        .fixedSize()
                        .position(placement)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
