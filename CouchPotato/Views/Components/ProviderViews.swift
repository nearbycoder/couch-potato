import SwiftUI

/// A rounded-square service mark: the TMDB logo when available, otherwise a
/// monogram on the brand color. No third-party logos are bundled.
struct ProviderTile: View {
    var provider: Provider
    var logoURL: URL?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let logoURL {
                RemoteImage(url: logoURL, maxPixel: size * 3, placeholderTitle: nil)
            } else {
                ZStack {
                    provider.color
                    Text(provider.monogram)
                        .font(.system(size: size * (provider.monogram.count > 2 ? 0.28 : 0.36), weight: .bold, design: .rounded))
                        .foregroundStyle(provider.color.luminance > 0.6 ? Color.black.opacity(0.85) : .white)
                        .minimumScaleFactor(0.6)
                        .padding(2)
                }
            }
        }
        .frame(width: size, height: size)
        .artwork(radius: size * 0.24)
        .accessibilityLabel(provider.name)
    }
}

/// A service with its name, used in "Where to Watch".
struct ProviderOfferView: View {
    var offer: ProviderOffer
    var isMine: Bool

    var body: some View {
        VStack(spacing: 6) {
            ProviderTile(provider: offer.provider, logoURL: offer.logoURL, size: 48)
                .overlay(alignment: .bottomTrailing) {
                    if isMine {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, Theme.success)
                            .offset(x: 4, y: 4)
                    }
                }
            Text(offer.provider.shortName)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let price = offer.price {
                Text(price).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(offer.provider.name), \(offer.kind.label)\(offer.price.map { ", \($0)" } ?? "")")
    }
}

/// A selectable service row/chip for Settings, onboarding and Browse.
struct ProviderChip: View {
    var provider: Provider
    var isSelected = false
    var showsCheck = true

    var body: some View {
        HStack(spacing: 8) {
            ProviderTile(provider: provider, size: 28)
            Text(provider.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if showsCheck {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
            } else {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? Theme.accent.opacity(0.6) : Theme.hairline))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.name)
        .accessibilityValue(showsCheck ? (isSelected ? "Selected" : "Not selected") : "")
    }
}

extension Color {
    /// Approximate relative luminance, used to pick legible monogram text.
    var luminance: Double {
        #if os(iOS)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        #endif
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }
}

/// A 1–5 star rating control.
struct StarRating: View {
    @Binding var value: Int
    var size: CGFloat = 26
    var editable = true

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= value ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i <= value ? Theme.accent : Theme.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .onTapGesture {
                        guard editable else { return }
                        withAnimation(.snappy) { value = value == i ? 0 : i }
                    }
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue("\(value) of 5 stars")
        .accessibilityAdjustableAction { direction in
            guard editable else { return }
            switch direction {
            case .increment: value = min(5, value + 1)
            case .decrement: value = max(0, value - 1)
            @unknown default: break
            }
        }
    }

    static func label(_ value: Int) -> String {
        switch value {
        case 1: "Not for me"
        case 2: "It was fine"
        case 3: "Good"
        case 4: "Great"
        case 5: "Favorite"
        default: "Tap to rate"
        }
    }
}

/// Community score, e.g. "★ 7.8".
struct ScoreLabel: View {
    var score: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.caption2)
            Text(String(format: "%.1f", score))
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .accessibilityLabel("Score \(String(format: "%.1f", score)) out of 10")
    }
}

/// Loads async content with standard loading and error states.
struct Loadable<Value, Content: View>: View {
    var id: String
    var load: () async throws -> Value
    @ViewBuilder var content: (Value) -> Content

    @State private var value: Value?
    @State private var error: Error?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if let error {
                EmptyState(symbol: "wifi.exclamationmark", title: "Couldn't load",
                           message: error.localizedDescription, actionTitle: "Try Again") { attempt += 1 }
            } else {
                LoadingView()
            }
        }
        .task(id: "\(id)#\(attempt)") {
            error = nil
            do {
                let loaded = try await load()
                value = loaded
            } catch is CancellationError {
            } catch {
                if value == nil { self.error = error }
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .tint(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 160)
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 4)
            Text(title).font(.headline).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
            Text(message).font(.footnote).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.primary).padding(.top, 8)
            }
        }
        .frame(maxWidth: 320)
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// A simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// "2024 · Drama · 1h 52m" style metadata for a title.
extension CatalogTitle {
    var metaLine: String {
        var bits: [String] = []
        if let year { bits.append(String(year)) }
        if let genre = genres.first { bits.append(genre) }
        if let runtime, runtime > 0 { bits.append(runtime.runtimeLabel) }
        if kind == .tv, let network, bits.count < 3 { bits.append(network) }
        return bits.joined(separator: " · ")
    }
}
