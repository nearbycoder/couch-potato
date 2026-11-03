import SwiftUI
import SwiftData

/// Shuffle: can't decide? Filter by mood and time, then let the deck pick.
struct ShuffleView: View {
    enum PoolSource: String, CaseIterable, Identifiable {
        case queue = "Watchlist", discover = "Discover"
        var id: String { rawValue }
    }

    @Environment(Catalog.self) private var catalog
    @Environment(AppModel.self) private var app
    @Environment(\.layout) private var layout
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedTitle.addedAt, order: .reverse) private var saved: [SavedTitle]

    @State private var source: PoolSource = .queue
    @State private var mood: Mood?
    @State private var budget: TimeBudget = .allNight
    @State private var discoverPool: [CatalogTitle] = []
    @State private var deck: [CatalogTitle] = []
    @State private var front = 0
    @State private var shuffling = false
    @State private var winner: CatalogTitle?
    @State private var ticks = 0

    private var pool: [CatalogTitle] {
        let base: [CatalogTitle] = source == .queue
            ? saved.filter { $0.status == .queued || $0.status == .watching }.map(\.asCatalogTitle)
            : discoverPool
        return base.filter { title in
            (mood == nil || source == .discover || mood!.matches(title)) &&
            (budget == .allNight || (title.runtime ?? 0) <= budget.rawValue)
        }
    }

    private var cardWidth: CGFloat { layout.isCompact ? 200 : 240 }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                controls

                ZStack {
                    if deck.count >= 2 {
                        Deck(deck: deck, front: front, width: cardWidth, shuffling: shuffling)
                    } else {
                        EmptyState(symbol: "shuffle",
                                   title: source == .queue ? "Not enough titles" : "Loading",
                                   message: source == .queue ? "Add at least two titles to your watchlist, or shuffle from Discover." : "Fetching titles to shuffle.",
                                   actionTitle: source == .queue ? "Use Discover" : nil) { source = .discover }
                    }
                }
                .frame(height: cardWidth * 1.5 + 48)
                .padding(.horizontal, cardWidth * 0.3)
                .sensoryFeedback(.impact(weight: .light), trigger: ticks)

                Button {
                    shuffle()
                } label: {
                    Label(shuffling ? "Shuffling" : "Shuffle", systemImage: "shuffle")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.primary)
                .disabled(shuffling || deck.count < 2)
                .keyboardShortcut("r", modifiers: .command)

                if let winner, !shuffling {
                    WinnerCard(title: winner) {
                        Library.save(winner, status: .watching, in: context)
                        app.push(.detail(winner))
                    } plan: {
                        app.plan(winner)
                    } again: {
                        shuffle()
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                    .padding(.horizontal, layout.margin)
                }
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle("Shuffle")
        .task(id: "\(source.rawValue)-\(mood?.rawValue ?? "")-\(catalog.hasTMDB)") {
            if source == .discover {
                if let mood {
                    discoverPool = (try? await catalog.mood(mood)) ?? []
                } else {
                    discoverPool = (try? await catalog.trending()) ?? []
                }
            }
            reloadDeck()
        }
        .onChange(of: budget) { reloadDeck() }
        .onChange(of: saved.count) { if source == .queue { reloadDeck() } }
        .onAppear {
            if saved.filter({ $0.status == .queued || $0.status == .watching }).count < 2 { source = .discover }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Pool", selection: $source) {
                ForEach(PoolSource.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Any mood", selected: mood == nil) { mood = nil }
                    ForEach(Mood.allCases) { m in
                        chip(m.title, symbol: m.symbol, selected: mood == m) { mood = m }
                    }
                }
                .padding(.horizontal, layout.margin)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Time").font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
                    ForEach(TimeBudget.allCases) { b in
                        chip(b.label, selected: budget == b) { budget = b }
                    }
                }
                .padding(.horizontal, layout.margin)
            }
        }
    }

    private func chip(_ text: String, symbol: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Pill(text: text, systemImage: symbol,
                 tint: selected ? Theme.textPrimary : Theme.fill,
                 foreground: selected ? Theme.bg : Theme.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func reloadDeck() {
        winner = nil
        deck = Array(pool.shuffled().prefix(12))
        front = 0
    }

    private func shuffle() {
        guard deck.count >= 2, !shuffling else { return }
        withAnimation(.easeOut(duration: 0.2)) { winner = nil }
        shuffling = true
        Task {
            var wait = 0.05
            let target = Int.random(in: 0..<deck.count)
            // Cycle quickly, then decelerate; the final tick lands on the target.
            while wait < 0.42 {
                try? await Task.sleep(for: .seconds(wait))
                withAnimation(.easeOut(duration: min(wait, 0.2))) { front = (front + 1) % deck.count }
                ticks += 1
                wait *= 1.17
            }
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                front = target
                winner = deck[target]
                shuffling = false
            }
        }
    }
}

/// Three stacked posters; the front one changes as the deck cycles.
struct Deck: View {
    var deck: [CatalogTitle]
    var front: Int
    var width: CGFloat
    var shuffling: Bool

    var body: some View {
        ZStack {
            ForEach((0..<min(3, deck.count)).reversed(), id: \.self) { depth in
                let title = deck[(front + depth) % deck.count]
                RemoteImage(url: title.posterURL, maxPixel: 600, placeholderTitle: title.name)
                    .frame(width: width, height: width * 1.5)
                    .artwork(radius: 14)
                    .softShadow(radius: depth == 0 ? 24 : 10, y: depth == 0 ? 14 : 6)
                    .scaleEffect(1 - CGFloat(depth) * 0.06)
                    .offset(x: depth == 1 ? -width * 0.22 : (depth == 2 ? width * 0.22 : 0), y: CGFloat(depth) * 10)
                    .opacity(depth == 0 ? 1 : (depth == 1 ? 0.75 : 0.6))
                    .rotationEffect(.degrees(depth == 1 ? -7 : (depth == 2 ? 7 : (shuffling ? Double(front % 2 == 0 ? 1.5 : -1.5) : 0))))
                    .zIndex(Double(3 - depth))
                    .id("\(depth)-\(title.id)")
            }
        }
        .animation(.easeOut(duration: 0.18), value: front)
        .accessibilityElement()
        .accessibilityLabel(shuffling ? "Shuffling" : "Front card: \(deck[front % max(deck.count, 1)].name)")
    }
}

struct WinnerCard: View {
    var title: CatalogTitle
    var watch: () -> Void
    var plan: () -> Void
    var again: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                RemoteImage(url: title.posterURL, maxPixel: 400, placeholderTitle: title.name)
                    .frame(width: 90, height: 135)
                    .artwork()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tonight's pick").font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                    Text(title.name).font(.title2.weight(.bold)).foregroundStyle(.white)
                    Text(title.metaLine).font(.footnote).foregroundStyle(.white.opacity(0.7))
                    if !title.overview.isEmpty {
                        Text(title.overview).font(.footnote).foregroundStyle(.white.opacity(0.8)).lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 10) { buttons }
            }
        }
        .padding(18)
        .frame(maxWidth: 560)
        .background {
            ZStack {
                RemoteImage(url: title.backdropURL ?? title.posterURL, maxPixel: 800, placeholderTitle: nil)
                    .blur(radius: 40)
                    .scaleEffect(1.4)
                Color.black.opacity(0.55)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .softShadow(radius: 20, y: 10)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var buttons: some View {
        Button("Watch Now", action: watch).buttonStyle(.primary)
        Button("Plan It", action: plan).buttonStyle(.secondary)
        Button("Shuffle Again", action: again).buttonStyle(.secondary)
    }
}
