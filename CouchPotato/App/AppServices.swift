import SwiftData
import SwiftUI

/// The app's long-lived services. One instance serves both the UI and App Intents:
/// Siri can launch the app in the background to run an intent, with no window open.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let prefs: Preferences
    let catalog: Catalog
    let app = AppModel()
    let sync: SyncMonitor
    let intelligence = Intelligence()
    let container: ModelContainer
    private(set) lazy var actions = CouchActions(services: self)

    var context: ModelContext { container.mainContext }

    private init() {
        prefs = Preferences()
        catalog = Catalog(prefs: prefs)
        let (container, cloudError) = Self.makeContainer()
        self.container = container
        sync = SyncMonitor(isCloudBacked: cloudError == nil, setupError: cloudError)
    }

    /// CloudKit-backed store when the app is signed with the iCloud entitlement,
    /// otherwise a plain local store (e.g. unsigned simulator builds). The second
    /// value says why sync is off, or nil when the store is CloudKit-backed.
    static func makeContainer() -> (ModelContainer, String?) {
        let schema = Schema([SavedTitle.self, CouchNight.self])
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        var reason = "Sync is off for test runs."
        if !inMemory, !SyncMonitor.hasCloudKitEntitlement {
            reason = "This build isn't signed for iCloud, so your library stays on this device."
        } else if !inMemory {
            do {
                let cloud = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic))
                return (cloud, nil)
            } catch {
                print("[Sync] CloudKit store unavailable, using a local store: \(error)")
                reason = "iCloud sync couldn't start on this build, so your library stays on this device."
            }
        }
        let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return (try! ModelContainer(for: schema, configurations: local), reason)
    }
}
