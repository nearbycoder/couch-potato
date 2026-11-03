import SwiftUI

/// A brand-colored service chip (text only; no third-party logos are bundled).
struct ProviderChip: View {
    var provider: Provider
    var logoURL: URL?
    var detail: String?
    var isMine = false
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            if let logoURL {
                RemoteImage(url: logoURL, maxPixel: 96, placeholderTitle: nil)
                    .frame(width: compact ? 18 : 24, height: compact ? 18 : 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text(provider.emoji).font(.system(size: compact ? 12 : 15))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(provider.shortName)
                    .font(Spud.display(compact ? 12 : 14, weight: .bold))
                if let detail {
                    Text(detail).font(.system(size: 10, weight: .semibold, design: .rounded)).opacity(0.85)
                }
            }
            if isMine {
                Image(systemName: "checkmark.circle.fill").font(.system(size: compact ? 11 : 13))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 7)
        .background(provider.color.gradient, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(isMine ? 0.9 : 0.15), lineWidth: isMine ? 2 : 1))
    }
}

struct ProviderDot: View {
    var provider: Provider

    var body: some View {
        Text(provider.shortName)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(provider.color, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
    }
}

/// A 1–5 potato rating control.
struct PotatoRating: View {
    @Binding var value: Int
    var size: CGFloat = 28
    var editable = true

    @State private var bounce: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Text("🥔")
                    .font(.system(size: size))
                    .grayscale(i <= value ? 0 : 1)
                    .opacity(i <= value ? 1 : 0.3)
                    .scaleEffect(bounce == i ? 1.35 : 1)
                    .rotationEffect(.degrees(bounce == i ? -12 : 0))
                    .onTapGesture {
                        guard editable else { return }
                        value = value == i ? 0 : i
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { bounce = i }
                        withAnimation(.spring().delay(0.25)) { bounce = nil }
                    }
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel("Potato rating")
        .accessibilityValue("\(value) of 5 potatoes")
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
        case 1: "Mashed it… badly"
        case 2: "Half-baked"
        case 3: "Solid spud"
        case 4: "Loaded & delicious"
        case 5: "Golden fry of perfection"
        default: "Tap a potato to rate"
        }
    }
}

/// Loads async content with Spud-themed loading/error states.
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
                SpudMessage(title: "Spud tripped over a cable",
                            message: error.localizedDescription,
                            expression: .wow,
                            actionTitle: "Try again") { attempt += 1 }
            } else {
                SpudLoading()
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

struct SpudLoading: View {
    var label = "Peeling the potatoes…"
    @State private var spin = false

    var body: some View {
        VStack(spacing: 10) {
            Text("🥔")
                .font(.system(size: 40))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
            Text(label).font(.spudCaption).foregroundStyle(Spud.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .onAppear { spin = true }
    }
}
