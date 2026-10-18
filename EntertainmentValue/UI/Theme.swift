import SwiftUI
import UIKit

/// Cream paper by day, navy by night, and the icon's six petal colours for
/// everything else.
enum Theme {
    static let paper = dynamic(light: (0.961, 0.929, 0.859), dark: (0.075, 0.114, 0.267))
    static let raised = dynamic(light: (1.0, 0.980, 0.941), dark: (0.106, 0.153, 0.325))
    static let ink = dynamic(light: (0.180, 0.122, 0.180), dark: (0.949, 0.925, 0.894))
    static let muted = dynamic(light: (0.420, 0.353, 0.388), dark: (0.682, 0.702, 0.800))
    static let line = dynamic(light: (0.890, 0.839, 0.749), dark: (0.173, 0.227, 0.431))
    static let idle = dynamic(light: (0.706, 0.663, 0.627), dark: (0.369, 0.404, 0.533))

    static func color(for kind: MediaKind) -> Color {
        switch kind {
        case .comic: dynamic(light: (0.867, 0.353, 0.275), dark: (0.925, 0.447, 0.384))
        case .film: dynamic(light: (0.886, 0.486, 0.275), dark: (0.941, 0.569, 0.369))
        case .podcast: dynamic(light: (0.753, 0.627, 0.165), dark: (0.851, 0.722, 0.259))
        case .game: dynamic(light: (0.133, 0.588, 0.510), dark: (0.239, 0.702, 0.616))
        case .tv: dynamic(light: (0.341, 0.412, 0.780), dark: (0.514, 0.580, 0.918))
        case .book: dynamic(light: (0.624, 0.459, 0.780), dark: (0.718, 0.588, 0.871))
        }
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    private static func dynamic(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }
}

extension MediaKind {
    var color: Color { Theme.color(for: self) }
}

struct PaperBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .foregroundStyle(Theme.ink)
    }
}

extension View {
    func paperBackground() -> some View { modifier(PaperBackground()) }
}

/// Section labels: small, rounded, spaced capitals.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.display(12, weight: .heavy))
            .kerning(1.2)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Decimal {
    /// "S$1.38", using the home currency.
    func money(code: String = "SGD") -> String {
        formatted(.currency(code: code).presentation(.narrow).precision(.fractionLength(2)))
    }
}

extension Double {
    /// "14.5 h", "45 min".
    var hoursLabel: String {
        if self < 60 { return "\(Int(self.rounded())) min" }
        let hours = self / 60
        return hours.formatted(.number.precision(.fractionLength(0...1))) + " h"
    }
}
