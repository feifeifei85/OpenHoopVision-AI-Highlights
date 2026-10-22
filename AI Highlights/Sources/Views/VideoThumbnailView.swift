import SwiftUI

struct VideoThumbnailView: View {
    let videoSource: VideoSourceReference?
    let allowsGeneration: Bool
    var timestamp: TimeInterval = 0
    var width: CGFloat = 96
    var height: CGFloat = 62
    @State private var image: UIImage?

    var body: some View {
        Color.hoopElevated
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.hoopMuted)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
            .task(id: ThumbnailRequest(videoSource: videoSource, allowsGeneration: allowsGeneration, timestamp: timestamp), priority: .utility) {
                image = nil
                guard let videoSource else { return }
                if let cached = await VideoThumbnailStore.shared.cachedImage(for: videoSource, at: timestamp) {
                    image = cached
                } else if allowsGeneration {
                    // A running analysis cancels this task; cached images stay visible.
                    if let generated = try? await VideoThumbnailStore.shared.image(for: videoSource, at: timestamp), !Task.isCancelled {
                        image = generated
                    }
                }
            }
    }
}

private struct ThumbnailRequest: Equatable {
    let videoSource: VideoSourceReference?
    let allowsGeneration: Bool
    let timestamp: TimeInterval
}
