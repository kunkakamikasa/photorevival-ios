import SwiftUI
import UIKit

/// Shared sizing rules for every user-upload preview in the app. Containers
/// own their dimensions; source-photo proportions never participate in layout.
enum UploadPreviewLayout {
    static let aspectRatio: CGFloat = 4.0 / 3.0

    /// The foreground always uses the preview's full height. Its width is
    /// derived from the source photo, so portrait photos reveal the frosted
    /// surround while wide photos crop horizontally without resizing the box.
    static func foregroundSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.height > 0 else {
            return containerSize
        }

        return CGSize(
            width: containerSize.height * imageSize.width / imageSize.height,
            height: containerSize.height
        )
    }
}

/// Displays an uploaded photo inside a caller-owned fixed frame: an enlarged,
/// blurred glass backdrop plus a proportional foreground at the frame's full
/// height. The view never derives or changes its container's dimensions.
struct FrostedUploadedPhoto: View {
    let image: UIImage

    var body: some View {
        GeometryReader { proxy in
            let foregroundSize = UploadPreviewLayout.foregroundSize(
                for: image.size,
                in: proxy.size
            )

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: 24)
                    .scaleEffect(1.18)

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.18)

                Color.black.opacity(0.08)

                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: foregroundSize.width, height: foregroundSize.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .background(Color(.systemGray4))
    }
}
