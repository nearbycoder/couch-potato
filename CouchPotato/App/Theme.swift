import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(cleaned, radix: 16) ?? 0x888888)
    }

    /// A color that adapts to light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(Color(hex: dark)) : NSColor(Color(hex: light))
        })
        #endif
    }
}

/// The Couch Potato palette: potato skins, butter, ketchup and a teal couch.
enum Spud {
    static let cream = Color(light: 0xFFF6E6, dark: 0x1E1612)
    static let card = Color(light: 0xFFFFFF, dark: 0x2B201A)
    static let cardRaised = Color(light: 0xFFEFD6, dark: 0x382A22)
    static let ink = Color(light: 0x3B2416, dark: 0xFFF1DC)
    static let inkSoft = Color(light: 0x8A6A52, dark: 0xC9AE93)
    static let potato = Color(hex: 0xC8935A)
    static let brown = Color(light: 0x6B4226, dark: 0xE2B486)
    static let butter = Color(hex: 0xFFD45C)
    static let teal = Color(light: 0x2F7F7A, dark: 0x4FB3AC)
    static let ketchup = Color(hex: 0xE5533D)
    static let lettuce = Color(hex: 0x7DBB5A)
    static let grape = Color(hex: 0x8E6AD8)

    static let corner: CGFloat = 18

    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Font {
    static let spudTitle = Spud.display(28)
    static let spudHeadline = Spud.display(19, weight: .bold)
    static let spudBody = Font.system(.body, design: .rounded)
    static let spudCaption = Font.system(.caption, design: .rounded).weight(.semibold)
}

/// A soft, sticker-like card background.
struct SpudCard: ViewModifier {
    var color: Color = Spud.card
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(color, in: RoundedRectangle(cornerRadius: Spud.corner, style: .continuous))
            .shadow(color: Spud.brown.opacity(0.12), radius: 0, x: 0, y: 4)
    }
}

extension View {
    func spudCard(_ color: Color = Spud.card, padding: CGFloat = 16) -> some View {
        modifier(SpudCard(color: color, padding: padding))
    }

    func spudBackground() -> some View {
        background(Spud.cream.ignoresSafeArea())
    }
}

/// A chunky, squishy button style with a hard drop shadow.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Spud.teal
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Spud.display(16, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(color, in: Capsule())
            .background(color.mix(with: .black, by: 0.35), in: Capsule().offset(y: configuration.isPressed ? 1 : 4))
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ChunkyButtonStyle {
    static var chunky: ChunkyButtonStyle { ChunkyButtonStyle() }
    static func chunky(_ color: Color, foreground: Color = .white) -> ChunkyButtonStyle {
        ChunkyButtonStyle(color: color, foreground: foreground)
    }
}

/// A rounded pill used for genres, moods and filters.
struct Pill: View {
    var text: String
    var systemImage: String?
    var color: Color = Spud.cardRaised
    var foreground: Color = Spud.ink

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.spudCaption)
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color, in: Capsule())
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String?
    var emoji: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let emoji { Text(emoji) }
                Text(title).font(.spudHeadline).foregroundStyle(Spud.ink)
            }
            if let subtitle {
                Text(subtitle).font(.spudCaption).foregroundStyle(Spud.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
