import SwiftData
import SwiftUI

/// Shown after finishing something. Both the rating and the note are
/// optional; swiping the sheet away saves nothing and loses nothing.
struct RatingSheet: View {
    let log: Log

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Double?
    @State private var note = ""

    var body: some View {
        let kind = log.item?.kind ?? .film
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(log.kind == .finished ? "Finished." : "How was it?")
                    .font(Theme.display(26, weight: .black))
                if let summary = finishSummary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
            RatingDial(rating: $rating, color: kind.color)
                .accessibilityIdentifier("ratingDial")
                .frame(height: 150)
            TextField("One sentence for future you?", text: $note, axis: .vertical)
                .accessibilityIdentifier("noteField")
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack {
                Button("Skip") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(kind.color)
                    .disabled(rating == nil && note.trimmingCharacters(in: .whitespaces).isEmpty
                        && log.rating == nil && log.note == nil)
            }
            .font(Theme.display(16, weight: .bold))
        }
        .padding(20)
        .presentationDetents([.height(420)])
        .presentationBackground(Theme.paper)
        .onAppear {
            rating = log.rating
            note = log.note ?? ""
        }
    }

    /// "47 hours across 3 months" for long things; nothing for a single sitting.
    private var finishSummary: String? {
        guard let item = log.item else { return nil }
        let logs = item.logs ?? []
        guard logs.count > 2 else { return item.title }
        let minutes = item.totalMinutes
        let first = logs.map(\.date).min() ?? log.date
        let months = max(1, Calendar.current.dateComponents([.month], from: first, to: log.date).month.map { $0 + 1 } ?? 1)
        let span = months == 1 ? "one month" : "\(months) months"
        return "\(item.title): \(minutes.hoursLabel) across \(span)."
    }

    private func save() {
        try? Library(context: context).rate(log, rating: rating, note: note)
        dismiss()
    }
}

/// A half-circle you drag a thumb across. Ten detents, one per half star,
/// each with a tick of haptic.
struct RatingDial: View {
    @Binding var rating: Double?
    let color: Color

    private static let lineWidth: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let geometry = DialGeometry(size: proxy.size, lineWidth: Self.lineWidth)
            let fraction = (rating ?? 0) / 5

            ZStack {
                DialArc(fraction: 1, geometry: geometry)
                    .stroke(Theme.line, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                DialArc(fraction: fraction, geometry: geometry)
                    .stroke(color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .animation(.spring(duration: 0.25, bounce: 0.4), value: fraction)
                VStack(spacing: 0) {
                    Text(rating.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "Rate")
                        .font(Theme.display(34, weight: .black))
                        .contentTransition(.numericText())
                    Text(rating == nil ? "drag along the arc" : "out of 5")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                .position(x: geometry.centre.x, y: geometry.centre.y - geometry.radius * 0.35)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        rating = geometry.rating(at: value.location)
                    }
            )
        }
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue(rating.map { "\($0.formatted()) out of 5" } ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            let current = rating ?? 0
            switch direction {
            case .increment: rating = min(5, current + 0.5)
            case .decrement: rating = current <= 0.5 ? nil : current - 0.5
            @unknown default: break
            }
        }
    }
}

/// Where the dial's half-circle sits inside its frame.
nonisolated struct DialGeometry: Hashable, Sendable {
    let centre: CGPoint
    let radius: CGFloat

    init(size: CGSize, lineWidth: CGFloat) {
        let inset = lineWidth / 2
        radius = max(1, min(size.width / 2, size.height) - inset)
        centre = CGPoint(x: size.width / 2, y: size.height - inset)
    }

    /// The point at a fraction along the arc, from the left end (0) over the
    /// top to the right end (1).
    func point(at fraction: Double) -> CGPoint {
        let angle = Double.pi * (1 - fraction.clamped(to: 0...1))
        return CGPoint(x: centre.x + radius * cos(angle), y: centre.y - radius * sin(angle))
    }

    /// Maps a touch to half-star steps: the left end is half a star, the
    /// right end five.
    func rating(at location: CGPoint) -> Double {
        let dx = Double(location.x - centre.x)
        let dy = Double(max(0, centre.y - location.y))
        let angle = atan2(dy, dx).clamped(to: 0...Double.pi)
        let fraction = 1 - angle / Double.pi
        let steps = (fraction * 10).rounded(.up).clamped(to: 1...10)
        return steps / 2
    }
}

/// The dial's arc, drawn from sampled points so the direction is never in doubt.
private struct DialArc: Shape {
    var fraction: Double
    let geometry: DialGeometry

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = fraction.clamped(to: 0...1)
        guard clamped > 0 else { return path }
        let steps = max(2, Int(clamped * 60))
        path.move(to: geometry.point(at: 0))
        for step in 1...steps {
            path.addLine(to: geometry.point(at: clamped * Double(step) / Double(steps)))
        }
        return path
    }
}
