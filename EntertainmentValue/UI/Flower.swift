import SwiftUI

/// One petal from the icon: a rounded pentagon pointing at the centre, drawn
/// in a 1024-point square with its tip just above the middle.
struct PetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 512, y: 418),
            CGPoint(x: 368, y: 269.9),
            CGPoint(x: 340, y: 84),
            CGPoint(x: 684, y: 84),
            CGPoint(x: 656, y: 269.9),
        ]
        let scale = min(rect.width, rect.height) / 1024
        var path = Path()
        path.addLines(points.map {
            CGPoint(x: rect.minX + $0.x * scale, y: rect.minY + ($0.y - 25) * scale)
        })
        path.closeSubpath()
        return path
    }
}

/// A petal with the icon's soft rounded corners.
struct Petal: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, proxy.size.height) * 90 / 1024
            PetalShape()
                .fill(color)
                .overlay(PetalShape().stroke(color, style: StrokeStyle(lineWidth: width, lineJoin: .round)))
        }
    }
}

/// The month's flower. Each petal grows with that medium's share of the
/// month's hours; an empty medium is a small, faint petal.
struct FlowerView: View {
    /// 0 to 1 per medium, from `ValueMath.flowerShares`.
    var shares: [MediaKind: Double]
    var emptyColor: Color = Theme.line

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(Array(MediaKind.allCases.enumerated()), id: \.element) { index, kind in
                    let share = shares[kind] ?? 0
                    Petal(color: share > 0 ? kind.color : emptyColor)
                        .frame(width: side, height: side)
                        .scaleEffect(scale(for: share) * 0.82, anchor: .center)
                        .rotationEffect(.degrees(Double(index) * 60))
                        .animation(.spring(duration: 0.4, bounce: 0.35), value: share)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func scale(for share: Double) -> Double {
        share > 0 ? 0.45 + 0.55 * share.squareRoot() : 0.32
    }

    private var accessibilityText: String {
        let ranked = shares.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map(\.key.pluralName)
        if ranked.isEmpty { return "This month's flower has no petals yet" }
        return "This month's flower. Most time on " + ranked.prefix(3).joined(separator: ", ")
    }
}

#Preview {
    FlowerView(shares: [.podcast: 1, .book: 0.4, .game: 0.4, .tv: 0.3, .film: 0.3, .comic: 0.03])
        .frame(width: 220)
        .padding()
}
