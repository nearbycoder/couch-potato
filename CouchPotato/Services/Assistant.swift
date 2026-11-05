import Foundation
import FoundationModels
import Observation

/// The in-app agent: a conversation with the on-device model that can act through tools
/// (find titles, check where to watch, update the watchlist, plan nights). The tools are
/// thin wrappers over CouchActions, the same layer Siri's App Intents use.
@MainActor
@Observable
final class Assistant {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        var role: Role
        var text: String
        var titles: [CatalogTitle] = []
        var isError = false
    }

    private(set) var messages: [Message] = []
    private(set) var isResponding = false

    @ObservationIgnored private let ledger = ToolLedger()
    @ObservationIgnored private var session: LanguageModelSession?
    @ObservationIgnored private var task: Task<Void, Never>?

    static let instructions = """
        You are Couch Potato's assistant, helping someone decide what to watch and manage \
        their watchlist and viewing plans. Always use the tools to look up titles, \
        availability and the watchlist; never invent titles or streaming services. When you \
        need a title's ID for another tool, use the ID from an earlier tool result. Refer \
        to titles by name, never by ID. The app shows posters for titles you find, so \
        mention at most three by name. Confirm what you did after taking an action. Keep \
        replies under 60 words, friendly and plain, with no emoji and no markdown.
        """

    func send(_ text: String) {
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isResponding else { return }
        messages.append(Message(role: .user, text: request))
        messages.append(Message(role: .assistant, text: ""))
        let index = messages.count - 1
        isResponding = true
        task = Task {
            defer { isResponding = false }
            do {
                try await respond(to: request, into: index)
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error {
                    // Long chats outgrow the on-device context window: start a fresh one.
                    session = nil
                    do { try await respond(to: request, into: index) } catch { fail(index, error) }
                } else {
                    fail(index, error)
                }
            } catch is CancellationError {
            } catch {
                fail(index, error)
            }
        }
    }

    func stop() { task?.cancel() }

    func reset() {
        task?.cancel()
        session = nil
        messages = []
    }

    private func respond(to request: String, into index: Int) async throws {
        ledger.begin(request: request)
        let session = self.session ?? makeSession()
        self.session = session
        for try await snapshot in session.streamResponse(to: request) {
            messages[index].text = snapshot.content
            messages[index].titles = ledger.titles
        }
        messages[index].titles = ledger.titles
        if messages[index].text.isEmpty { messages[index].text = "Done." }
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(tools: [
            FindTitlesTool(ledger: ledger),
            SearchByNameTool(ledger: ledger),
            WatchlistTool(ledger: ledger),
            UpdateWatchlistTool(ledger: ledger),
            WhereToWatchTool(ledger: ledger),
            PlanNightTool(ledger: ledger),
            PickForTonightTool(ledger: ledger),
            PlannedNightsTool(),
        ], instructions: Self.instructions)
    }

    private func fail(_ index: Int, _ error: Error) {
        let message: String
        if let generation = error as? LanguageModelSession.GenerationError, case .guardrailViolation = generation {
            message = "I can't help with that one. Try asking about something to watch."
        } else if error is URLError {
            message = "I couldn't reach the catalog. Check your connection and try again."
        } else {
            message = "Something went wrong. Try asking another way."
        }
        messages[index].text = message
        messages[index].isError = true
    }
}

/// Collects the titles tools surface during one reply, so the chat can show posters.
@MainActor
final class ToolLedger: Sendable {
    private(set) var titles: [CatalogTitle] = []
    private(set) var request = ""

    func begin(request: String) {
        self.request = request
        titles = []
    }

    func show(_ new: [CatalogTitle]) {
        let known = Set(titles.map(\.id))
        titles += new.filter { !known.contains($0.id) }
    }

    /// One compact line per title, which keeps tool output small for the context window.
    func describe(_ list: [CatalogTitle], limit: Int = 8) -> String {
        guard !list.isEmpty else { return "No titles found." }
        let context = AppServices.shared.context
        return list.prefix(limit).map { title in
            var parts = ["id: \(title.id)", title.name]
            parts.append([title.year.map(String.init), title.kind == .movie ? "movie" : "series"].compactMap { $0 }.joined(separator: " "))
            if !title.genres.isEmpty { parts.append(title.genres.prefix(3).joined(separator: ", ")) }
            if let score = title.score { parts.append(String(format: "rated %.1f", score)) }
            if let runtime = title.runtime { parts.append("\(runtime) min") }
            if let saved = Library.saved(title.id, in: context) { parts.append("in watchlist: \(saved.status.label)") }
            return parts.joined(separator: " | ")
        }.joined(separator: "\n")
    }
}

// MARK: - Tools

struct FindTitlesTool: Tool {
    let ledger: ToolLedger
    let name = "findTitles"
    let description = "Finds movies and series that match what the person describes: a genre, mood, era, rating, length or streaming service."

    func call(arguments: WatchQuery) async throws -> String {
        try await onMain {
            // Drop anything the person didn't actually ask for, as the Ask screen does.
            let query = arguments.validated(against: ledger.request)
            let titles = AppServices.shared.actions.remember(try await AppServices.shared.catalog.ask(query))
            ledger.show(Array(titles.prefix(8)))
            return ledger.describe(titles)
        }
    }
}

struct SearchByNameTool: Tool {
    let ledger: ToolLedger
    let name = "searchByName"
    let description = "Looks up a specific movie or series by its name."

    @Generable
    struct Arguments {
        @Guide(description: "The title's name")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await onMain {
            let titles = try await AppServices.shared.actions.search(arguments.name)
            ledger.show(Array(titles.prefix(4)))
            return ledger.describe(titles, limit: 5)
        }
    }
}

struct WatchlistTool: Tool {
    let ledger: ToolLedger
    let name = "getWatchlist"
    let description = "Lists the titles on the person's watchlist with a given status."

    @Generable
    struct Arguments {
        @Guide(description: "Which part of the watchlist")
        var status: StatusChoice
    }

    func call(arguments: Arguments) async throws -> String {
        try await onMain {
            let items = AppServices.shared.actions.library([arguments.status.status])
            let titles = items.map(\.asCatalogTitle)
            ledger.show(Array(titles.prefix(8)))
            return items.isEmpty ? "Nothing is marked \(arguments.status.status.label)." : ledger.describe(titles, limit: 12)
        }
    }
}

struct UpdateWatchlistTool: Tool {
    let ledger: ToolLedger
    let name = "updateWatchlist"
    let description = "Adds a title to the watchlist, changes its status, or removes it."

    @Generable
    struct Arguments {
        @Guide(description: "The title's ID from an earlier result, or its exact name")
        var title: String
        @Guide(description: "The new status, or remove")
        var action: UpdateChoice
    }

    func call(arguments: Arguments) async throws -> String {
        try await onMain {
            let actions = AppServices.shared.actions
            let title = try await actions.title(named: arguments.title)
            ledger.show([title])
            if arguments.action == .remove {
                actions.remove(title.id)
                return "Removed \(title.name) from the watchlist."
            }
            let saved = actions.setStatus(arguments.action.status, for: title)
            return "\(title.name) is now marked \(saved.status.label)."
        }
    }
}

struct WhereToWatchTool: Tool {
    let ledger: ToolLedger
    let name = "whereToWatch"
    let description = "Finds which services stream, rent or sell a title in the person's region."

    @Generable
    struct Arguments {
        @Guide(description: "The title's ID from an earlier result, or its exact name")
        var title: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await onMain {
            let actions = AppServices.shared.actions
            let title = try await actions.title(named: arguments.title)
            ledger.show([title])
            return actions.whereToWatchSentence(title, try await actions.availability(of: title))
        }
    }
}

struct PlanNightTool: Tool {
    let ledger: ToolLedger
    let name = "planNight"
    let description = "Schedules a night to watch a title, with a reminder."

    @Generable
    struct Arguments {
        @Guide(description: "The title's ID from an earlier result, or its exact name")
        var title: String
        @Guide(description: "Days from today: 0 for tonight, 1 for tomorrow", .range(0...30))
        var daysFromToday: Int
        @Guide(description: "Hour on a 24-hour clock, 20 if not given", .range(0...23))
        var hour: Int
        @Guide(description: "Minute", .range(0...59))
        var minute: Int
    }

    func call(arguments: Arguments) async throws -> String {
        try await onMain {
            let actions = AppServices.shared.actions
            let title = try await actions.title(named: arguments.title)
            ledger.show([title])
            let day = Calendar.current.date(byAdding: .day, value: arguments.daysFromToday, to: .now) ?? .now
            let date = Calendar.current.date(bySettingHour: arguments.hour, minute: arguments.minute, second: 0, of: day) ?? day
            let night = await actions.planNight(title, at: date)
            return "Planned \(title.name) for \(night.startsAt.formatted(.dateTime.weekday(.wide).month().day().hour().minute())), with a reminder."
        }
    }
}

struct PickForTonightTool: Tool {
    let ledger: ToolLedger
    let name = "pickForTonight"
    let description = "Picks one title from the person's watchlist for tonight, optionally matching a mood or time limit."

    @Generable
    struct Arguments {
        @Guide(description: "A mood, or none")
        var mood: WatchQuery.MoodChoice
        @Guide(description: "Minutes available, or 0 for no limit", .range(0...600))
        var maxMinutes: Int
    }

    func call(arguments: Arguments) async throws -> String {
        try await onMain {
            let pick = try await AppServices.shared.actions.shuffle(
                mood: Mood(rawValue: arguments.mood.rawValue), maxMinutes: arguments.maxMinutes > 0 ? arguments.maxMinutes : nil)
            ledger.show([pick])
            return "Pick: " + ledger.describe([pick])
        }
    }
}

struct PlannedNightsTool: Tool {
    let name = "getPlannedNights"
    let description = "Lists the viewing nights the person has planned."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        try await onMain {
            let nights = AppServices.shared.actions.upcomingNights()
            guard !nights.isEmpty else { return "No nights are planned." }
            return nights.prefix(10).map {
                "\($0.titleName) | \($0.startsAt.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))"
            }.joined(separator: "\n")
        }
    }
}

@Generable
enum StatusChoice: String {
    case queued, watching, watched, dropped
    var status: WatchStatus { WatchStatus(rawValue: rawValue) ?? .queued }
}

@Generable
enum UpdateChoice: String {
    case queued, watching, watched, dropped, remove
    var status: WatchStatus { WatchStatus(rawValue: rawValue) ?? .queued }
}

/// Tools run off the main actor; the app's data lives on it.
private func onMain<T: Sendable>(_ work: @escaping @MainActor () async throws -> T) async throws -> T {
    try await Task { @MainActor in try await work() }.value
}
