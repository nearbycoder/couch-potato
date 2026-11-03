import Foundation
import Observation

/// User settings, mirrored to iCloud key-value storage so your services, region
/// and TMDB key follow you between iPhone, iPad and Mac.
@MainActor
@Observable
final class Preferences {
    var myServiceIDs: Set<String> { didSet { save("myServices", Array(myServiceIDs).sorted()) } }
    var region: String { didSet { save("region", region) } }
    var tmdbKey: String { didSet { save("tmdbKey", tmdbKey) } }
    var onlyMyServices: Bool { didSet { save("onlyMyServices", onlyMyServices) } }
    var nickname: String { didSet { save("nickname", nickname) } }
    var remindMinutesBefore: Int { didSet { save("remindMinutesBefore", remindMinutesBefore) } }
    var addNightsToCalendar: Bool { didSet { save("addNightsToCalendar", addNightsToCalendar) } }
    var newEpisodeAlerts: Bool { didSet { save("newEpisodeAlerts", newEpisodeAlerts) } }

    /// Device-local: whether the welcome sheet has been shown here.
    var hasOnboarded: Bool { didSet { UserDefaults.standard.set(hasOnboarded, forKey: "hasOnboarded") } }

    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private let cloud = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private var observer: NSObjectProtocol?

    static let regions: [(code: String, name: String)] = [
        ("US", "United States"), ("CA", "Canada"), ("GB", "United Kingdom"), ("AU", "Australia"),
        ("NZ", "New Zealand"), ("IE", "Ireland"), ("DE", "Germany"), ("FR", "France"), ("ES", "Spain"),
        ("IT", "Italy"), ("NL", "Netherlands"), ("SE", "Sweden"), ("BR", "Brazil"), ("MX", "Mexico"),
        ("IN", "India"), ("JP", "Japan"), ("KR", "South Korea"),
    ]

    /// A key baked in at build time via `Config/Secrets.xcconfig`, if any.
    static var bundledTMDBKey: String {
        let key = (Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String) ?? ""
        return key.hasPrefix("$(") ? "" : key
    }

    init() {
        let defaults = UserDefaults.standard
        myServiceIDs = Set(defaults.stringArray(forKey: "myServices") ?? [])
        region = defaults.string(forKey: "region") ?? (Locale.current.region?.identifier ?? "US")
        tmdbKey = defaults.string(forKey: "tmdbKey") ?? ""
        onlyMyServices = defaults.bool(forKey: "onlyMyServices")
        nickname = defaults.string(forKey: "nickname") ?? ""
        remindMinutesBefore = defaults.object(forKey: "remindMinutesBefore") as? Int ?? 15
        addNightsToCalendar = defaults.bool(forKey: "addNightsToCalendar")
        newEpisodeAlerts = defaults.object(forKey: "newEpisodeAlerts") as? Bool ?? true
        hasOnboarded = defaults.bool(forKey: "hasOnboarded")
        if !Self.regions.contains(where: { $0.code == region }) { region = "US" }

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullFromCloud() }
        }
        cloud.synchronize()
        pullFromCloud()
    }

    var effectiveTMDBKey: String {
        let typed = tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? Self.bundledTMDBKey : typed
    }

    var myServices: [Provider] { Provider.streamers.filter { myServiceIDs.contains($0.id) } }

    func toggle(_ provider: Provider) {
        if myServiceIDs.contains(provider.id) { myServiceIDs.remove(provider.id) } else { myServiceIDs.insert(provider.id) }
    }

    func isMine(_ provider: Provider) -> Bool { myServiceIDs.contains(provider.id) }

    private func save(_ key: String, _ value: Any) {
        guard !isLoading else { return }
        UserDefaults.standard.set(value, forKey: key)
        cloud.set(value, forKey: key)
    }

    private func pullFromCloud() {
        isLoading = true
        defer { isLoading = false }
        if let services = cloud.array(forKey: "myServices") as? [String] { myServiceIDs = Set(services) }
        if let region = cloud.string(forKey: "region"), !region.isEmpty { self.region = region }
        if let key = cloud.string(forKey: "tmdbKey") { tmdbKey = key }
        if cloud.object(forKey: "onlyMyServices") != nil { onlyMyServices = cloud.bool(forKey: "onlyMyServices") }
        if let nickname = cloud.string(forKey: "nickname") { self.nickname = nickname }
        if let minutes = cloud.object(forKey: "remindMinutesBefore") as? Int { remindMinutesBefore = minutes }
        if cloud.object(forKey: "addNightsToCalendar") != nil { addNightsToCalendar = cloud.bool(forKey: "addNightsToCalendar") }
        if cloud.object(forKey: "newEpisodeAlerts") != nil { newEpisodeAlerts = cloud.bool(forKey: "newEpisodeAlerts") }
        // Mirror whatever we accepted locally so a later launch without iCloud matches.
        let defaults = UserDefaults.standard
        defaults.set(Array(myServiceIDs).sorted(), forKey: "myServices")
        defaults.set(region, forKey: "region")
        defaults.set(tmdbKey, forKey: "tmdbKey")
        defaults.set(onlyMyServices, forKey: "onlyMyServices")
        defaults.set(nickname, forKey: "nickname")
    }
}
