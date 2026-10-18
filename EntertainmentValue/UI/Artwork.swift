import SwiftUI
import UIKit

/// A cover, or a block in the medium's colour while it loads or when there is
/// none.
struct ArtworkView: View {
    let url: URL?
    let kind: MediaKind
    var cornerRadius: CGFloat = 10

    @Environment(AppServices.self) private var services
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                kind.color
                Image(systemName: kind.symbolName)
                    .font(.system(size: max(12, proxy.size.width * 0.32), weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(image == nil ? 1 : 0)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: url) { await load(size: proxy.size) }
        }
        .accessibilityHidden(true)
    }

    private func load(size: CGSize) async {
        guard let url, let artwork = services.artwork, size.width > 1 else {
            image = nil
            return
        }
        do {
            let data = try await artwork.data(for: url)
            let decoded = await ArtworkDownsampler.image(from: data, targetSize: size, displayScale: displayScale)
            withAnimation(.easeOut(duration: 0.2)) { image = decoded }
        } catch {
            image = nil
        }
    }
}
