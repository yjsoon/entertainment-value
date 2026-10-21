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
    /// Text on the ink-coloured hero card, which flips with the theme.
    static let onInk = dynamic(light: (1.0, 0.980, 0.941), dark: (0.180, 0.122, 0.180))
    static let onInkMuted = dynamic(light: (0.851, 0.800, 0.827), dark: (0.420, 0.353, 0.388))

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

    /// Bricolage Grotesque, bundled as static cuts: a "Text" optical size for
    /// small type and a tighter "Display" cut for 24 pt and up. Sizes scale
    /// with Dynamic Type relative to the nearest text style.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .custom(BricolageCut.name(size: size, weight: weight), size: size, relativeTo: textStyle(for: size))
    }

    /// Body copy in the same family.
    static func text(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font {
        display(size, weight: weight)
    }

    static let body = text(17)
    static let subheadline = text(15)
    static let footnote = text(13)
    static let caption = text(12)

    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: .caption2
        case ..<13: .caption
        case ..<15: .footnote
        case ..<16: .subheadline
        case ..<18: .body
        case ..<21: .title3
        case ..<26: .title2
        case ..<32: .title
        default: .largeTitle
        }
    }

    /// Nonisolated on purpose: SwiftUI resolves colours on its render thread
    /// during animations, and a main-actor closure here traps.
    nonisolated private static func dynamic(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(uiColor: UIColor { @Sendable traits in
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

/// The bundled font files. Display cuts only come in the heavier weights.
nonisolated enum BricolageCut {
    static func name(size: CGFloat, weight: Font.Weight) -> String {
        let style: String
        switch weight {
        case .ultraLight, .thin, .light, .regular: style = "Regular"
        case .medium: style = "Medium"
        case .semibold: style = "SemiBold"
        case .bold: style = "Bold"
        default: style = "ExtraBold"
        }
        let usesDisplay = size >= 24 && ["SemiBold", "Bold", "ExtraBold"].contains(style)
        return "Bricolage\(usesDisplay ? "Display" : "Text")-\(style)"
    }

    static let files = [
        "BricolageText-Regular", "BricolageText-Medium", "BricolageText-SemiBold",
        "BricolageText-Bold", "BricolageText-ExtraBold",
        "BricolageDisplay-SemiBold", "BricolageDisplay-Bold", "BricolageDisplay-ExtraBold",
    ]
}

/// Section labels: a short bold line, no shouting capitals.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.display(15, weight: .bold))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

nonisolated extension Decimal {
    /// "S$1.38", using the home currency.
    func money(code: String = "SGD") -> String {
        formatted(.currency(code: code).presentation(.narrow).precision(.fractionLength(2)))
    }
}

nonisolated extension Double {
    /// "45 min", "2h", "9h 30m". Rounded to the nearest 5 minutes past an hour.
    var hoursLabel: String {
        let total = Int(max(0, self).rounded())
        if total < 60 { return "\(total) min" }
        let rounded = Int((Double(total) / 5).rounded()) * 5
        let hours = rounded / 60
        let minutes = rounded % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
