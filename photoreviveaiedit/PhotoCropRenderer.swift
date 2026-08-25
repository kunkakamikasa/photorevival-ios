import UIKit

enum PhotoCropAspect: String, CaseIterable, Identifiable {
    case original = "ORIGINAL"
    case freeform = "FREEFORM"
    case square = "1:1"
    case portraitHalf = "1:2"
    case landscapeDouble = "2:1"
    case portraitFourThree = "3:4"
    case landscapeFourThree = "4:3"
    case portraitSixteenNine = "9:16"
    case landscapeSixteenNine = "16:9"

    var id: String { rawValue }

    func value(for imageSize: CGSize, freeformValue: CGFloat) -> CGFloat {
        switch self {
        case .original:
            guard imageSize.height > 0 else { return 1 }
            return imageSize.width / imageSize.height
        case .freeform:
            return max(0.15, min(freeformValue, 6.5))
        case .square:
            return 1
        case .portraitHalf:
            return 1 / 2
        case .landscapeDouble:
            return 2
        case .portraitFourThree:
            return 3 / 4
        case .landscapeFourThree:
            return 4 / 3
        case .portraitSixteenNine:
            return 9 / 16
        case .landscapeSixteenNine:
            return 16 / 9
        }
    }
}

enum PhotoCropRenderer {
    static func normalized(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.scale == 1, image.cgImage != nil {
            return image
        }

        let pixelSize = CGSize(
            width: max(1, image.size.width * image.scale),
            height: max(1, image.size.height * image.scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }

    static func rotatedClockwise(_ image: UIImage) -> UIImage {
        let source = normalized(image)
        let outputSize = CGSize(width: source.size.height, height: source.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: outputSize.width / 2, y: outputSize.height / 2)
            cgContext.rotate(by: .pi / 2)
            source.draw(
                in: CGRect(
                    x: -source.size.width / 2,
                    y: -source.size.height / 2,
                    width: source.size.width,
                    height: source.size.height
                )
            )
        }
    }

    static func flippedHorizontally(_ image: UIImage) -> UIImage {
        let source = normalized(image)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: source.size, format: format).image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: source.size.width, y: 0)
            cgContext.scaleBy(x: -1, y: 1)
            source.draw(in: CGRect(origin: .zero, size: source.size))
        }
    }

    static func cropFrameSize(in availableSize: CGSize, aspectRatio: CGFloat) -> CGSize {
        guard availableSize.width > 0, availableSize.height > 0 else { return .zero }
        let ratio = max(0.15, min(aspectRatio, 6.5))
        let availableRatio = availableSize.width / availableSize.height

        if ratio > availableRatio {
            return CGSize(width: availableSize.width, height: availableSize.width / ratio)
        }
        return CGSize(width: availableSize.height * ratio, height: availableSize.height)
    }

    static func clampedOffset(
        _ offset: CGSize,
        imageSize: CGSize,
        viewportSize: CGSize,
        zoom: CGFloat
    ) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else { return .zero }

        let baseScale = max(
            viewportSize.width / imageSize.width,
            viewportSize.height / imageSize.height
        )
        let displayScale = baseScale * max(1, zoom)
        let maximumX = max(0, (imageSize.width * displayScale - viewportSize.width) / 2)
        let maximumY = max(0, (imageSize.height * displayScale - viewportSize.height) / 2)

        return CGSize(
            width: min(max(offset.width, -maximumX), maximumX),
            height: min(max(offset.height, -maximumY), maximumY)
        )
    }

    static func croppedImage(
        from image: UIImage,
        viewportSize: CGSize,
        zoom: CGFloat,
        offset: CGSize
    ) -> UIImage? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }
        let source = normalized(image)
        guard let cgImage = source.cgImage else { return nil }

        let baseScale = max(
            viewportSize.width / source.size.width,
            viewportSize.height / source.size.height
        )
        let displayScale = baseScale * max(1, zoom)
        let safeOffset = clampedOffset(
            offset,
            imageSize: source.size,
            viewportSize: viewportSize,
            zoom: zoom
        )
        let cropWidth = min(source.size.width, viewportSize.width / displayScale)
        let cropHeight = min(source.size.height, viewportSize.height / displayScale)
        let maximumX = source.size.width - cropWidth
        let maximumY = source.size.height - cropHeight
        let cropX = min(
            max(source.size.width / 2 - safeOffset.width / displayScale - cropWidth / 2, 0),
            maximumX
        )
        let cropY = min(
            max(source.size.height / 2 - safeOffset.height / displayScale - cropHeight / 2, 0),
            maximumY
        )
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
            .intersection(CGRect(origin: .zero, size: source.size))

        guard cropRect.width >= 1, cropRect.height >= 1,
              let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCGImage, scale: 1, orientation: .up)
    }
}
