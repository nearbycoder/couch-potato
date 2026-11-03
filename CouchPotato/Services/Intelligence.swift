import Foundation
import FoundationModels
import Observation

/// On-device Apple Intelligence (the Foundation Models framework). Nothing here leaves
/// the device. Every feature is optional: when the model isn't available (older
/// hardware, Apple Intelligence off, model still downloading) the UI hides it.
@MainActor
@Observable
final class Intelligence {
    private let model = SystemLanguageModel.default

    var isAvailable: Bool { model.isAvailable }

    /// Why the model can't be used, phrased for Settings; nil when it's ready.
    var unavailableReason: String? {
        switch model.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings to use these features."
        case .unavailable(.modelNotReady): "Apple Intelligence is still getting ready. Try again soon."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    // MARK: Ask

    /// Turns a request like "a cozy mystery series from the last few years" into filters.
    func interpret(_ request: String) async throws -> WatchQuery {
        let session = LanguageModelSession(instructions: """
            You turn a person's request for something to watch into search filters for a \
            streaming guide. Leave every field at its default (any, none, 0, an empty list or \
            an empty string) unless the request explicitly says it. Use keywords only for a \
            specific title, person or franchise. Never invent services, ratings or time limits.
            """)
        let response = try await session.respond(to: request, generating: WatchQuery.self,
                                                 options: GenerationOptions(temperature: 0.2))
        return response.content.validated(against: request)
    }

    // MARK: Shuffle

    /// A short, spoiler-free pitch for tonight's pick, streamed as it's written.
    func pitch(for title: CatalogTitle, mood: Mood?, minutes: Int?) -> AsyncThrowingStream<String, Error> {
        let session = LanguageModelSession(instructions: """
            You're a friend recommending what to watch tonight. Write one or two sentences, \
            at most 35 words, warm and specific. No spoilers beyond the premise, no emoji, no \
            hashtags. Don't start with the title's name and don't use the word "perfect".
            """)
        var facts = ["Title: \(title.name)", "Type: \(title.kind.label)"]
        if let year = title.year { facts.append("Year: \(year)") }
        if !title.genres.isEmpty { facts.append("Genres: \(title.genres.prefix(4).joined(separator: ", "))") }
        if let runtime = title.runtime { facts.append("Runtime: \(runtime) minutes") }
        if !title.overview.isEmpty { facts.append("Premise: \(title.overview.prefix(600))") }
        if let mood { facts.append("They're in the mood for: \(mood.title.lowercased()) (\(mood.blurb.lowercased()))") }
        if let minutes { facts.append("Time they have: about \(minutes) minutes") }
        let prompt = facts.joined(separator: "\n")

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.8)) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// What the model extracts from a free-text request. Field names and enum cases match
/// the Android app's JSON so both platforms interpret requests the same way.
@Generable
struct WatchQuery: Equatable {
    @Generable
    enum Kind: String { case any, movie, series }

    @Generable
    enum GenreChoice: String {
        case none, action, animation, comedy, crime, documentary, drama, family, scifi, horror, mystery, romance, reality
    }

    @Generable
    enum YearsChoice: String { case any, thisYear, last5, y2020s, y2010s, y2000s, y1990s, older }

    @Generable
    enum SortChoice: String { case popular, newest, rating }

    @Generable
    enum MoodChoice: String { case none, cozy, laughs, thrills, feels, spooky, brainy }

    @Generable
    enum Service: String {
        case netflix, hulu, disney, hbo, apple, prime, peacock, paramount, starz, amc, crunchyroll, tubi, youtube
    }

    @Guide(description: "Movies, series, or any")
    var kind: Kind
    @Guide(description: "The genre asked for, or none")
    var genre: GenreChoice
    @Guide(description: "Release period asked for, e.g. last5 for 'recent', or any")
    var years: YearsChoice
    @Guide(description: "Minimum rating out of 10: 0 for no minimum, or 6, 7 or 8 for 'good', 'great', 'best'", .range(0...8))
    var minRating: Int
    @Guide(description: "popular unless they ask for the newest or the best rated")
    var sort: SortChoice
    @Guide(description: "A mood if the request is about a feeling rather than a genre, otherwise none")
    var mood: MoodChoice
    @Guide(description: "Longest runtime in minutes they have time for, or 0 for no limit", .range(0...600))
    var maxMinutes: Int
    @Guide(description: "Streaming services they named, if any")
    var services: [Service]
    @Guide(description: "Specific titles, people or topics to search for, or an empty string")
    var keywords: String
    @Guide(description: "A short headline restating the request, e.g. 'Recent sci-fi series on Netflix'")
    var summary: String
}

extension WatchQuery {
    /// Small models over-fill fields, so keep only what the request actually supports.
    /// The Android app applies the same rules.
    func validated(against request: String) -> WatchQuery {
        let text = request.lowercased()
        let words = Set(text.split { !$0.isLetter && !$0.isNumber && $0 != "+" }.map(String.init))
        func mentions(_ terms: [String]) -> Bool {
            terms.contains { term in term.contains(" ") || term.contains("+") ? text.contains(term) : words.contains(term) }
        }
        var query = self
        let serviceTerms: [Service: [String]] = [
            .netflix: ["netflix"], .hulu: ["hulu"], .disney: ["disney", "disney+", "disney plus"],
            .hbo: ["hbo", "max"], .apple: ["apple"], .prime: ["prime", "amazon"], .peacock: ["peacock"],
            .paramount: ["paramount", "paramount+"], .starz: ["starz"], .amc: ["amc", "amc+"],
            .crunchyroll: ["crunchyroll"], .tubi: ["tubi"], .youtube: ["youtube"],
        ]
        query.services = services.filter { mentions(serviceTerms[$0] ?? []) }
        if !(text.contains { $0.isNumber } || mentions(["minute", "minutes", "min", "mins", "hour", "hours", "hr", "short", "quick"])) {
            query.maxMinutes = 0
        }
        if !mentions(["good", "great", "best", "top", "highly", "acclaimed", "rated", "rating", "award", "awards"]) {
            query.minRating = 0
        }
        if genre != .none || mood != .none || years != .any || !query.services.isEmpty {
            query.keywords = ""
        }
        return query
    }

    /// Looser versions to fall back on when nothing matches, most specific first.
    var relaxations: [WatchQuery] {
        var steps: [WatchQuery] = []
        var query = self
        if query.maxMinutes > 0 { query.maxMinutes = 0; steps.append(query) }
        if query.minRating > 0 { query.minRating = 0; steps.append(query) }
        if query.years != .any { query.years = .any; steps.append(query) }
        if !query.services.isEmpty { query.services = []; steps.append(query) }
        return steps
    }

    var mediaKind: MediaKind? {
        switch kind {
        case .any: nil
        case .movie: .movie
        case .series: .tv
        }
    }

    var filter: TitleFilter {
        var filter = TitleFilter()
        filter.sort = switch sort {
        case .popular: .popular
        case .newest: .newest
        case .rating: .rating
        }
        filter.years = TitleFilter.Years(rawValue: years.rawValue) ?? .any
        filter.genre = TitleFilter.Genre(rawValue: genre.rawValue)
        filter.minRating = TitleFilter.ratingSteps.last { Double(minRating) >= $0 }
        return filter
    }

    var moodValue: Mood? { Mood(rawValue: mood.rawValue) }
    var providers: [Provider] { services.compactMap { Provider.with(id: $0.rawValue) } }
    var trimmedKeywords: String { keywords.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The interpreted filters as short labels, for read-only chips.
    var labels: [String] {
        var labels: [String] = []
        if let kind = mediaKind { labels.append(kind == .movie ? "Movies" : "Series") }
        if let genre = filter.genre { labels.append(genre.label) }
        if let mood = moodValue { labels.append(mood.title) }
        if filter.years != .any { labels.append(filter.years.label) }
        if let rating = filter.minRating { labels.append("\(Int(rating))+ Rating") }
        if filter.sort != .popular { labels.append(filter.sort.label) }
        if maxMinutes > 0 { labels.append("Under \(maxMinutes.runtimeLabel)") }
        labels += providers.map(\.name)
        if !trimmedKeywords.isEmpty { labels.append("“\(trimmedKeywords)”") }
        return labels
    }
}
