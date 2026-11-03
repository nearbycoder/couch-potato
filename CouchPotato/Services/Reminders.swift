import Foundation
import UserNotifications
import EventKit

/// Local notifications for couch nights and new episodes of followed shows.
@MainActor
enum Reminders {
    private static var center: UNUserNotificationCenter { .current() }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(_ night: CouchNight, minutesBefore: Int) async {
        cancel(night)
        guard night.remind, !night.isDone else { return }
        let fireDate = night.startsAt.addingTimeInterval(TimeInterval(-minutesBefore * 60))
        guard fireDate > .now, await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time to watch"
        content.body = minutesBefore > 0
            ? "\(night.titleName) starts in \(minutesBefore) minutes."
            : "\(night.titleName) is starting now."
        content.sound = .default
        content.userInfo = ["titleKey": night.titleKey]
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "night-\(night.id.uuidString)", content: content, trigger: trigger))
    }

    static func cancel(_ night: CouchNight) {
        center.removePendingNotificationRequests(withIdentifiers: ["night-\(night.id.uuidString)"])
    }

    static func scheduleNewEpisode(_ episode: EpisodeInfo) async {
        guard let airDate = episode.airDate, airDate > .now else { return }
        // Date-only air dates land at midnight; nudge those to 6pm local.
        var fire = airDate
        let parts = Calendar.current.dateComponents([.hour, .minute], from: airDate)
        if parts.hour == 0 && parts.minute == 0 { fire = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: airDate) ?? airDate }
        let content = UNMutableNotificationContent()
        content.title = "New episode: \(episode.showName)"
        content.body = "\(episode.code) · \(episode.name) is out now."
        content.sound = .default
        content.userInfo = ["titleKey": episode.showRef.key]
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "ep-\(episode.id)", content: content, trigger: trigger))
    }
}

/// Adds couch nights to the system calendar (write-only access).
@MainActor
enum CalendarBridge {
    private static let store = EKEventStore()

    static func add(_ night: CouchNight) async -> String? {
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = night.titleName
        event.startDate = night.startsAt
        event.endDate = night.endsAt
        event.notes = [night.note, "Planned with Couch Potato"].filter { !$0.isEmpty }.joined(separator: "\n\n")
        event.url = TitleRef(key: night.titleKey)?.deepLink
        event.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }
}
