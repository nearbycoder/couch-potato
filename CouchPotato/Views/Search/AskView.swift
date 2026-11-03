import SwiftUI

/// "Ask Couch Potato": describe what you want in your own words; the on-device model
/// turns it into filters and the catalog does the rest.
struct AskView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(Intelligence.self) private var intelligence
    @Environment(\.layout) private var layout

    @State private var request = ""
    @State private var query: WatchQuery?
    @State private var results: [CatalogTitle] = []
    @State private var phase: Phase = .idle
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    enum Phase: Equatable { case idle, thinking, searching, done, failed(String) }

    private let examples = [
        "Something funny under an hour",
        "A cozy mystery series",
        "Highly rated sci-fi from the last 5 years",
        "A thriller on Netflix",
        "Feel-good movies for the family",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                field
                content
            }
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .navigationTitle("Ask")
        .inlineTitle()
        .onAppear { if query == nil { focused = true } }
        .onDisappear { task?.cancel() }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
                TextField("Describe what you want to watch", text: $request, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit(run)
                if !request.isEmpty {
                    Button { request = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))

            HStack {
                Label("Runs on this device with Apple Intelligence", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button(action: run) {
                    Text("Find")
                }
                .buttonStyle(.primary)
                .disabled(request.trimmingCharacters(in: .whitespaces).count < 3 || phase == .thinking || phase == .searching)
            }
        }
        .padding(.horizontal, layout.margin)
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle:
            VStack(alignment: .leading, spacing: 12) {
                Text("Try").font(.sectionTitle).foregroundStyle(Theme.textPrimary)
                FlowLayout(spacing: 8) {
                    ForEach(examples, id: \.self) { example in
                        Button {
                            request = example
                            run()
                        } label: {
                            Pill(text: example, tint: Theme.fill, foreground: Theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, layout.margin)
        case .thinking:
            status("Understanding your request…")
        case .searching:
            VStack(alignment: .leading, spacing: 16) {
                summary
                status("Finding titles…")
            }
        case .failed(let message):
            EmptyState(symbol: "exclamationmark.bubble", title: "Couldn't understand that", message: message,
                       actionTitle: "Try Again", action: run)
        case .done:
            VStack(alignment: .leading, spacing: 18) {
                summary
                if results.isEmpty {
                    EmptyState(symbol: "rectangle.on.rectangle.slash", title: "No matches",
                               message: "Nothing fits that yet. Try loosening it, like dropping the year or rating.")
                } else {
                    PosterGrid(titles: results)
                }
            }
        }
    }

    @ViewBuilder private var summary: some View {
        if let query {
            VStack(alignment: .leading, spacing: 10) {
                Text(query.summary.isEmpty ? "Results" : query.summary)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !query.labels.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(query.labels, id: \.self) { label in
                            Pill(text: label, tint: Theme.accent.opacity(0.16), foreground: Theme.accent)
                        }
                    }
                }
            }
            .padding(.horizontal, layout.margin)
        }
    }

    private func status(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, layout.margin)
    }

    private func run() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return }
        focused = false
        task?.cancel()
        task = Task {
            phase = .thinking
            results = []
            do {
                let interpreted = try await intelligence.interpret(text)
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { query = interpreted }
                phase = .searching
                let found = try await catalog.ask(interpreted)
                guard !Task.isCancelled else { return }
                results = found
                withAnimation(.snappy) { phase = .done }
            } catch is CancellationError {
            } catch {
                phase = .failed(Self.describe(error))
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if error is URLError { return "Check your connection and try again." }
        return "Try rephrasing, like “a funny series from the 2010s”."
    }
}

/// Entry point at the top of Browse, shown only when Apple Intelligence is available.
struct AskCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button { app.push(.ask) } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Couch Potato").font(.headline).foregroundStyle(Theme.textPrimary)
                    Text("Describe what you're in the mood for")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Find something to watch by describing it")
    }
}
