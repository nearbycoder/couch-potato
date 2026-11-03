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

/// Design tokens (see DESIGN.md). Dark is the primary appearance.
enum Theme {
    static let bg = Color(light: 0xF5F5F7, dark: 0x0C0C10)
    static let surface = Color(light: 0xFFFFFF, dark: 0x15151B)
    static let surfaceElevated = Color(light: 0xFFFFFF, dark: 0x1D1D25)
    static let hairline = Color.primary.opacity(0.08)
    static let fill = Color.primary.opacity(0.09)
    static let textPrimary = Color(light: 0x111114, dark: 0xF5F5F7)
    static let textSecondary = Color.primary.opacity(0.62)
    static let textTertiary = Color.primary.opacity(0.40)
    static let accent = Color(light: 0xD98A1C, dark: 0xF0A335)
    static let onAccent = Color(hex: 0x1A1200)
    static let success = Color(light: 0x1E9E62, dark: 0x3DD68C)
    static let danger = Color(light: 0xD63E45, dark: 0xF2545B)
    static let info = Color(light: 0x2F6FE0, dark: 0x4C8DFF)

    static let cardRadius: CGFloat = 16
    static let posterRadius: CGFloat = 10
}

extension Font {
    static let sectionTitle = Font.title3.weight(.semibold)
    static let seeAll = Font.subheadline.weight(.medium)
    static let posterTitle = Font.subheadline.weight(.semibold)
    static let meta = Font.footnote
    static let captionStrong = Font.caption.weight(.medium)
}

/// Responsive sizes derived from the horizontal size class, so iPhone, the unfolded
/// iPhone Duo, iPad and Mac each get appropriate densities.
struct LayoutMetrics {
    var isCompact: Bool

    var posterWidth: CGFloat { isCompact ? 118 : 150 }
    var gridMinWidth: CGFloat { isCompact ? 100 : 156 }
    var heroHeight: CGFloat { isCompact ? 460 : 420 }
    var margin: CGFloat { isCompact ? 16 : 24 }
    var detailPosterWidth: CGFloat { isCompact ? 110 : 160 }
}

private struct LayoutKey: EnvironmentKey {
    static let defaultValue = LayoutMetrics(isCompact: true)
}

extension EnvironmentValues {
    var layout: LayoutMetrics {
        get { self[LayoutKey.self] }
        set { self[LayoutKey.self] = newValue }
    }
}

// MARK: - Surfaces

/// Soft, low shadow that adapts to the appearance.
struct SoftShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = 12
    var y: CGFloat = 6

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.10), radius: radius, y: y)
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.hairline))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
    func softShadow(radius: CGFloat = 12, y: CGFloat = 6) -> some View { modifier(SoftShadow(radius: radius, y: y)) }
    func appBackground() -> some View { background(Theme.bg.ignoresSafeArea()) }

    /// Rounded artwork with the hairline border every poster gets.
    func artwork(radius: CGFloat = Theme.posterRadius) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var foreground: Color = Theme.onAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .frame(minHeight: ButtonMetrics.height)
            .background(tint, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 18)
            .frame(minHeight: ButtonMetrics.height)
            .background(Theme.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

enum ButtonMetrics {
    static var height: CGFloat {
        #if os(macOS)
        36
        #else
        44
        #endif
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primary(_ tint: Color, foreground: Color = Theme.onAccent) -> PrimaryButtonStyle {
        PrimaryButtonStyle(tint: tint, foreground: foreground)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Small pieces

struct Pill: View {
    var text: String
    var systemImage: String?
    var dot: Color?
    var tint: Color = Theme.fill
    var foreground: Color = Theme.textPrimary

    var body: some View {
        HStack(spacing: 5) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.semibold)) }
            Text(text)
        }
        .font(.captionStrong)
        .foregroundStyle(foreground)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint, in: Capsule())
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sectionTitle).foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle).font(.meta).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The app mark: a couch silhouette, used in About and empty states.
struct BrandMark: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x23232D), Color(hex: 0x0B0B0F)], startPoint: .top, endPoint: .bottom))
            Image(systemName: "sofa.fill")
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(Color(hex: 0xF0A335))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
