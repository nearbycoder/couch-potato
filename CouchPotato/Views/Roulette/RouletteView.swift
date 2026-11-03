import SwiftUI
import SwiftData

/// Spud Roulette: can't decide? Spin the wheel.
struct RouletteView: View {
    enum PoolSource: String, CaseIterable, Identifiable {
        case queue = "My Queue", trending = "Surprise Me"
        var id: String { rawValue }
    }

    @Environment(Catalog.self) private var catalog
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedTitle.addedAt, order: .reverse) private var saved: [SavedTitle]

    @State private var source: PoolSource = .queue
    @State private var mood: Mood?
    @State private var budget: TimeBudget = .allNight
    @State private var surprisePool: [CatalogTitle] = []
    @State private var wheel: [CatalogTitle] = []
    @State private var rotation: Double = 0
    @State private var spinning = false
    @State private var winner: CatalogTitle?
    @State private var ticks = 0

    private var pool: [CatalogTitle] {
        let base: [CatalogTitle] = source == .queue
            ? saved.filter { $0.status == .queued || $0.status == .watching }.map(\.asCatalogTitle)
            : surprisePool
        return base.filter { title in
            (mood == nil || source == .trending || mood!.matches(title)) &&
            (budget == .allNight || (title.runtime ?? 0) <= budget.rawValue)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                controls
                ZStack {
                    WheelView(titles: wheel, rotation: rotation)
                        .frame(maxWidth: 420)
                        .aspectRatio(1, contentMode: .fit)
                    if wheel.count < 2 {
                        VStack(spacing: 10) {
                            SpudMascot(size: 70, expression: .sleepy)
                            Text(source == .queue ? "Not enough spuds in your queue for these filters." : "Spud is fetching surprises…")
                                .font(.spudBody).foregroundStyle(Spud.ink).multilineTextAlignment(.center)
                            if source == .queue {
                                Button("Surprise me instead") { source = .trending }
                                    .buttonStyle(.chunky(Spud.teal))
                            }
                        }
                        .frame(maxWidth: 240)
                        .spudCard(padding: 20)
                    }
                }
                .overlay(alignment: .top) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Spud.ketchup)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
                        .offset(y: -14)
                }
                .padding(.horizontal, 24)
                .sensoryFeedback(.impact(weight: .light), trigger: ticks)

                Button {
                    spin()
                } label: {
                    Label(spinning ? "Spinning…" : "Spin the Spud!", systemImage: "dice.fill")
                        .font(Spud.display(20))
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.chunky(Spud.ketchup))
                .disabled(spinning || wheel.count < 2)
                .keyboardShortcut("r", modifiers: .command)

                if let winner, !spinning {
                    WinnerCard(title: winner) {
                        Library.save(winner, status: .watching, in: context)
                        app.paths[app.selection, default: NavigationPath()].append(Route.detail(winner))
                    } plan: {
                        app.plan(winner)
                    } again: {
                        spin()
                    }
                    .transition(.scale.combined(with: .opacity))
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity)
        }
        .spudBackground()
        .navigationTitle("Spud Roulette")
        .task(id: "\(source.rawValue)-\(mood?.rawValue ?? "")-\(catalog.hasTMDB)") {
            if source == .trending {
                if let mood {
                    surprisePool = (try? await catalog.mood(mood)) ?? []
                } else {
                    surprisePool = (try? await catalog.trending()) ?? []
                }
            }
            reloadWheel()
        }
        .onChange(of: budget) { reloadWheel() }
        .onAppear {
            if saved.filter({ $0.status == .queued || $0.status == .watching }).count < 2 { source = .trending }
        }
        .onChange(of: saved.count) { if source == .queue { reloadWheel() } }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Pool", selection: $source) {
                ForEach(PoolSource.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { mood = nil } label: {
                        Pill(text: "Any vibe", color: mood == nil ? Spud.butter : Spud.card, foreground: mood == nil ? Color(hex: 0x3B2416) : Spud.ink)
                    }
                        .buttonStyle(.plain)
                    ForEach(Mood.allCases) { m in
                        Button { mood = m } label: {
                            Pill(text: "\(m.emoji) \(m.title)", color: mood == m ? m.color : Spud.card,
                                 foreground: mood == m ? Color(hex: 0x2A1A10) : Spud.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 8) {
                Text("I've got:").font(.spudCaption).foregroundStyle(Spud.inkSoft)
                ForEach(TimeBudget.allCases) { b in
                    Button { budget = b } label: {
                        Pill(text: "\(b.emoji) \(Device.isPhone ? b.label.components(separatedBy: " (").first! : b.label)",
                             color: budget == b ? Spud.teal : Spud.card, foreground: budget == b ? .white : Spud.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func reloadWheel() {
        winner = nil
        wheel = Array(pool.shuffled().prefix(8))
    }

    private func spin() {
        guard wheel.count >= 2, !spinning else { return }
        winner = nil
        spinning = true
        let seg = 360.0 / Double(wheel.count)
        let target = Int.random(in: 0..<wheel.count)
        // Land in the middle-ish of the target wedge under the top pointer.
        let jitter = Double.random(in: -seg * 0.3...seg * 0.3)
        let desired = 360 - (Double(target) + 0.5) * seg + jitter
        let current = rotation.truncatingRemainder(dividingBy: 360)
        let delta = (desired - current + 720).truncatingRemainder(dividingBy: 360)
        let duration = 3.6
        withAnimation(.timingCurve(0.15, 0.85, 0.25, 1, duration: duration)) {
            rotation += 360 * 6 + delta
        }
        Task {
            // Clicky haptics that slow down with the wheel.
            var wait = 0.04
            var elapsed = 0.0
            while elapsed < duration - 0.3 {
                try? await Task.sleep(for: .seconds(wait))
                elapsed += wait
                ticks += 1
                wait *= 1.12
            }
            try? await Task.sleep(for: .seconds(max(0, duration - elapsed)))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                winner = wheel[target]
                spinning = false
            }
        }
    }
}

struct WheelView: View {
    var titles: [CatalogTitle]
    var rotation: Double

    private let colors: [Color] = [Spud.ketchup, Spud.butter, Spud.teal, Spud.potato, Spud.grape, Spud.lettuce, Color(hex: 0x5B8DEF), Color(hex: 0xF29E4C)]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let count = max(titles.count, 1)
            let seg = 360.0 / Double(count)
            ZStack {
                Circle().fill(Spud.brown).frame(width: size + 16, height: size + 16)
                ForEach(Array(titles.enumerated()), id: \.element.id) { i, title in
                    let start = -90 + Double(i) * seg
                    Path { p in
                        p.move(to: center)
                        p.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + seg), clockwise: false)
                        p.closeSubpath()
                    }
                    .fill(colors[i % colors.count].gradient)
                    .overlay(
                        Path { p in
                            p.move(to: center)
                            p.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + seg), clockwise: false)
                            p.closeSubpath()
                        }
                        .stroke(Spud.brown, lineWidth: 3)
                    )
                    let mid = (start + seg / 2) * .pi / 180
                    RemoteImage(url: title.posterURL, maxPixel: 200, placeholderTitle: nil)
                        .frame(width: radius * 0.34, height: radius * 0.51)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: 2))
                        .rotationEffect(.degrees(start + seg / 2 + 90))
                        .position(x: center.x + cos(mid) * radius * 0.64, y: center.y + sin(mid) * radius * 0.64)
                }
                if titles.count < 2 {
                    Circle().fill(Spud.cardRaised).frame(width: size, height: size)
                } else {
                    Circle().fill(Spud.cream).frame(width: radius * 0.42)
                        .overlay(Circle().stroke(Spud.brown, lineWidth: 4))
                    Text("🥔").font(.system(size: radius * 0.22))
                }
            }
            .rotationEffect(.degrees(rotation))
        }
    }
}

struct WinnerCard: View {
    var title: CatalogTitle
    var watch: () -> Void
    var plan: () -> Void
    var again: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("🎉 Spud has spoken! 🎉").font(Spud.display(18)).foregroundStyle(Spud.ketchup)
            HStack(spacing: 16) {
                RemoteImage(url: title.posterURL, maxPixel: 400, placeholderTitle: title.name)
                    .frame(width: 100, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.name).font(Spud.display(22)).foregroundStyle(Spud.ink)
                    Text(title.subtitle).font(.spudCaption).foregroundStyle(Spud.inkSoft)
                    if !title.overview.isEmpty {
                        Text(title.overview).font(.system(size: 13, design: .rounded)).foregroundStyle(Spud.inkSoft).lineLimit(4)
                    }
                }
                Spacer(minLength: 0)
            }
            ViewThatFits {
                HStack { buttons }
                VStack { buttons }
            }
        }
        .frame(maxWidth: 520)
        .spudCard(padding: 18)
    }

    @ViewBuilder private var buttons: some View {
        Button("Let's watch!", action: watch).buttonStyle(.chunky(Spud.teal))
        Button("Plan it", action: plan).buttonStyle(.chunky(Spud.brown))
        Button("Nah, spin again", action: again).buttonStyle(.chunky(Spud.cardRaised, foreground: Spud.ink))
    }
}
