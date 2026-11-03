import SwiftUI

/// Spud: the googly-eyed potato who lives on your couch. Drawn entirely in SwiftUI.
struct SpudMascot: View {
    enum Expression { case happy, wow, sleepy, wink }

    var size: CGFloat = 80
    var expression: Expression = .happy
    var bobbing = true
    /// -1…1 horizontal gaze for the pupils.
    var gaze: CGFloat = 0

    @State private var bob = false
    @State private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PotatoShape()
                .fill(
                    RadialGradient(colors: [Color(hex: 0xE2B07A), Spud.potato, Color(hex: 0xA8743F)],
                                   center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.75)
                )
                .overlay(PotatoShape().stroke(Color(hex: 0x6B4226), lineWidth: size * 0.035))

            // Potato eyes (the freckly kind).
            ForEach(Array(freckles.enumerated()), id: \.offset) { _, f in
                Ellipse()
                    .fill(Color(hex: 0x8C5A2E).opacity(0.55))
                    .frame(width: size * 0.06, height: size * 0.045)
                    .offset(x: f.x * size, y: f.y * size)
            }

            HStack(spacing: size * 0.08) {
                eye(isWinking: false)
                eye(isWinking: expression == .wink)
            }
            .offset(y: -size * 0.1)

            HStack(spacing: size * 0.36) {
                Circle().fill(Spud.ketchup.opacity(0.35)).frame(width: size * 0.14)
                Circle().fill(Spud.ketchup.opacity(0.35)).frame(width: size * 0.14)
            }
            .offset(y: size * 0.07)

            mouth.offset(y: size * 0.16)
        }
        .frame(width: size, height: size * 1.05)
        .offset(y: bob ? -size * 0.04 : size * 0.02)
        .rotationEffect(.degrees(bob ? -2 : 2))
        .accessibilityLabel("Spud the couch potato")
        .onAppear {
            guard bobbing, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5...5)))
                withAnimation(.easeInOut(duration: 0.08)) { blink = true }
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeInOut(duration: 0.08)) { blink = false }
            }
        }
    }

    private let freckles: [CGPoint] = [.init(x: -0.3, y: -0.28), .init(x: 0.27, y: -0.32), .init(x: 0.33, y: 0.3), .init(x: -0.22, y: 0.36)]

    @ViewBuilder
    private func eye(isWinking: Bool) -> some View {
        let w = size * 0.24
        if expression == .sleepy || isWinking || blink {
            Capsule().fill(Color(hex: 0x3B2416)).frame(width: w * 0.8, height: size * 0.035)
                .frame(width: w, height: w)
        } else {
            ZStack {
                Circle().fill(.white)
                Circle().stroke(Color(hex: 0x3B2416), lineWidth: size * 0.02)
                Circle()
                    .fill(Color(hex: 0x24150C))
                    .frame(width: w * (expression == .wow ? 0.38 : 0.5))
                    .overlay(Circle().fill(.white).frame(width: w * 0.14).offset(x: -w * 0.08, y: -w * 0.08))
                    .offset(x: gaze * w * 0.18, y: expression == .wow ? 0 : w * 0.06)
            }
            .frame(width: w, height: w)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch expression {
        case .wow:
            Ellipse().fill(Color(hex: 0x3B2416)).frame(width: size * 0.13, height: size * 0.16)
        case .sleepy:
            Capsule().fill(Color(hex: 0x3B2416)).frame(width: size * 0.12, height: size * 0.03)
        case .happy, .wink:
            SmileShape()
                .fill(Color(hex: 0x3B2416))
                .frame(width: size * 0.26, height: size * 0.12)
        }
    }
}

struct PotatoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.02))
        p.addCurve(to: CGPoint(x: w * 0.97, y: h * 0.42), control1: CGPoint(x: w * 0.8, y: h * 0.0), control2: CGPoint(x: w * 0.98, y: h * 0.18))
        p.addCurve(to: CGPoint(x: w * 0.55, y: h * 0.98), control1: CGPoint(x: w * 0.96, y: h * 0.7), control2: CGPoint(x: w * 0.82, y: h * 0.99))
        p.addCurve(to: CGPoint(x: w * 0.04, y: h * 0.6), control1: CGPoint(x: w * 0.25, y: h * 0.98), control2: CGPoint(x: w * 0.02, y: h * 0.85))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.02), control1: CGPoint(x: w * 0.06, y: h * 0.28), control2: CGPoint(x: w * 0.22, y: h * 0.04))
        p.closeSubpath()
        return p
    }
}

struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.15))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return p
    }
}

/// A friendly empty/error state with Spud front and center.
struct SpudMessage: View {
    var title: String
    var message: String
    var expression: SpudMascot.Expression = .happy
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            SpudMascot(size: 92, expression: expression)
            Text(title).font(Spud.display(22)).foregroundStyle(Spud.ink).multilineTextAlignment(.center)
            Text(message).font(.spudBody).foregroundStyle(Spud.inkSoft).multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.chunky).padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HStack {
        SpudMascot(expression: .happy)
        SpudMascot(expression: .wow)
        SpudMascot(expression: .sleepy)
        SpudMascot(expression: .wink)
    }
    .padding()
}
