import SwiftUI
import UIKit

/// Hoplite's palette, lifted from the web app's CSS variables (`--background`,
/// `--card`, `--action`, `--status-*`) and converted from OKLCH to sRGB.
enum HP {
    static let action = Color(hex: 0xFF3616)
    static let actionBright = Color(hex: 0xFF632A)
    static let actionDeep = Color(hex: 0xD21F00)
    static let actionSoft = Color(hex: 0xFFA799)

    static let canvas = Color(light: 0xEFEFEF, dark: 0x0F0F0F)
    static let surface = Color(light: 0xF7F7F7, dark: 0x161616)
    static let card = Color(light: 0xFFFFFF, dark: 0x1B1B1B)
    static let raised = Color(light: 0xFFFFFF, dark: 0x222222)
    static let bubble = Color(light: 0xE4E4E4, dark: 0x212121)
    static let inset = Color(light: 0xE8E8E8, dark: 0x131313)
    static let control = Color(light: 0xE6E6E6, dark: 0x292929)

    static let ink = Color(light: 0x121212, dark: 0xEEEEEE)
    static let ink2 = Color(light: 0x5B5B5B, dark: 0xA4A4A4)
    static let ink3 = Color(light: 0x8E8E8E, dark: 0x6F6F6F)
    static let hairline = Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.08)
    static let hairlineStrong = Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.14)

    static let running = Color(hex: 0x42A3FD)
    static let blocked = Color(hex: 0xF93F4E)
    static let ready = Color(hex: 0x43A84C)
    static let failed = Color(hex: 0xF4514F)
    static let waiting = Color(hex: 0xE7A13C)
    static let archived = Color(hex: 0x808080)
    static let merged = Color(hex: 0xA371F7)
    static let info = Color(hex: 0x6E9BFF)

    static let codeInk = Color(light: 0xB42400, dark: 0xFFB4A3)

    static let addition = Color(hex: 0x3FB950)
    static let deletion = Color(hex: 0xF85149)

    static let pageGutter: CGFloat = 20
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    /// SwiftUI resolves dynamic colors on its async render thread, so the provider must not be
    /// main-actor isolated (the module's default) or the runtime isolation check traps.
    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { @Sendable traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Typography. Funnel Display for headlines, Funnel Sans for interface text, Geist Mono for
/// code and identifiers, and Redaction's dithered italic as the brand accent: the same four
/// faces hoplite.sh uses. Every size scales with Dynamic Type.
extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("Funnel Display", size: size, relativeTo: style).weight(weight)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Funnel Sans", size: size, relativeTo: style).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .footnote) -> Font {
        .custom("Geist Mono", size: size, relativeTo: style).weight(weight)
    }

    static func pixel(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("Redaction35-Italic", size: size, relativeTo: style)
    }

    static let hpTitle = Font.display(30, weight: .medium)
    static let hpHeadline = Font.ui(17, weight: .semibold, relativeTo: .headline)
    static let hpBody = Font.ui(16.5, relativeTo: .body)
    static let hpCallout = Font.ui(15, relativeTo: .callout)
    static let hpSubhead = Font.ui(14, relativeTo: .subheadline)
    static let hpFootnote = Font.ui(13, relativeTo: .footnote)
    static let hpCaption = Font.ui(12, weight: .medium, relativeTo: .caption)
    static let hpEyebrow = Font.mono(11, weight: .medium, relativeTo: .caption2)
}

enum Appearance {
    static func configure() {
        let large = UIFont(name: "FunnelDisplay-Medium", size: 34) ?? .systemFont(ofSize: 34, weight: .semibold)
        let inline = UIFont(name: "FunnelSans-Medium", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large), .kern: -0.6]
        nav.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)]
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = HP.ink3

    var body: some View {
        Text(text.uppercased())
            .font(.hpEyebrow)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

extension View {
    /// Hoplite's card: a quiet surface with a hairline edge rather than a drop shadow.
    func hpCard(radius: CGFloat = 22, fill: Color = HP.card) -> some View {
        background(fill, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(HP.hairline, lineWidth: 1))
    }
}
