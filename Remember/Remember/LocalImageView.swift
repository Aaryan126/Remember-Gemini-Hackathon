import ImageIO
import SwiftUI
import UIKit

struct LocalImageView: View {
    let url: URL
    var maximumPixelSize = 1_200
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    RememberPalette.inset
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(RememberPalette.secondaryText)
                }
            }
        }
        .task(id: url) {
            image = await Task.detached(priority: .utility) {
                Self.downsample(url: url, maximumPixelSize: maximumPixelSize)
            }.value
        }
    }

    nonisolated private static func downsample(url: URL, maximumPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}
