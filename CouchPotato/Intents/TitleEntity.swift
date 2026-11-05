import AppIntents
import CoreSpotlight
import Foundation

/// A movie or series, as Siri, Shortcuts and Spotlight see it. Watchlist titles are
/// indexed (IndexedEntity) so Siri can answer from your library; the title page you're
/// looking at is annotated on its NSUserActivity so "add this to my watchlist" works.
struct TitleEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Title", numericFormat: "\(placeholder: .int) titles")
    static let defaultQuery = TitleEntityQuery()

    /// The stable title key, e.g. "tvmaze-tv-53647".
    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Type")
    var kind: String

    @Property(title: "Year")
    var year: Int?

    @Property(title: "Genres")
    var genres: String

    @Property(title: "Overview")
    var overview: String

    @Property(title: "Watchlist Status")
    var status: String?

    @Property(title: "Rating")
    var rating: Int?

    var posterURL: URL?

    var displayRepresentation: DisplayRepresentation {
        var subtitle = [year.map(String.init), kind].compactMap { $0 }.joined(separator: " · ")
        if let status { subtitle += " · \(status)" }
        return DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)",
                                     image: posterURL.map { DisplayRepresentation.Image(url: $0) })
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = overview
        attributes.keywords = [kind, status].compactMap { $0 } + genres.split(separator: ",").map(String.init)
        return attributes
    }

    init(_ title: CatalogTitle, status: WatchStatus? = nil, rating: Int? = nil) {
        id = title.ref.key
        posterURL = title.posterURL
        self.name = title.name
        self.kind = title.kind == .movie ? "Movie" : "Series"
        self.year = title.year
        self.genres = title.genres.joined(separator: ",")
        self.overview = title.overview
        self.status = status?.label
        self.rating = rating.flatMap { $0 > 0 ? $0 : nil }
    }

    @MainActor
    init(_ saved: SavedTitle) {
        self.init(saved.asCatalogTitle, status: saved.status, rating: saved.potatoes)
    }
}

struct TitleEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [TitleEntity.ID]) async throws -> [TitleEntity] {
        let actions = AppServices.shared.actions
        var result: [TitleEntity] = []
        for key in identifiers {
            if let saved = Library.saved(key, in: AppServices.shared.context) {
                result.append(TitleEntity(saved))
            } else if let title = try? await actions.title(key) {
                result.append(TitleEntity(title))
            }
        }
        return result
    }

    @MainActor
    func entities(matching string: String) async throws -> [TitleEntity] {
        try await AppServices.shared.actions.search(string).prefix(20).map(entity)
    }

    @MainActor
    func suggestedEntities() async throws -> [TitleEntity] {
        AppServices.shared.actions.library([.queued, .watching]).prefix(30).map(TitleEntity.init)
    }

    /// Library status included when the title is saved.
    @MainActor
    private func entity(_ title: CatalogTitle) -> TitleEntity {
        if let saved = Library.saved(title.ref.key, in: AppServices.shared.context) { return TitleEntity(saved) }
        return TitleEntity(title)
    }
}

enum WatchStatusEntity: String, AppEnum {
    case queued, watching, watched, dropped

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Watchlist Status")
    static let caseDisplayRepresentations: [WatchStatusEntity: DisplayRepresentation] = [
        .queued: "Want to Watch", .watching: "Watching", .watched: "Watched", .dropped: "Dropped",
    ]

    var status: WatchStatus { WatchStatus(rawValue: rawValue) ?? .queued }
}

enum MoodEntity: String, AppEnum {
    case cozy, laughs, thrills, feels, spooky, brainy

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Mood")
    static let caseDisplayRepresentations: [MoodEntity: DisplayRepresentation] = [
        .cozy: "Cozy", .laughs: "Laughs", .thrills: "Thrills", .feels: "Feels", .spooky: "Spooky", .brainy: "Brainy",
    ]

    var mood: Mood { Mood(rawValue: rawValue) ?? .cozy }
}
