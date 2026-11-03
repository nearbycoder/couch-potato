import CloudKit
import CoreData
import MachO
import Observation
#if os(macOS)
import Security
#endif

/// Watches the CloudKit mirror behind SwiftData so Settings can say whether sync is
/// really running, when it last ran, and what went wrong. SwiftData doesn't surface
/// this itself, but its NSPersistentCloudKitContainer still posts event notifications.
@MainActor
@Observable
final class SyncMonitor {
    enum Account: Equatable { case unknown, available, noAccount, restricted, unavailable }

    static let containerID = "iCloud.com.nearbycoder.couchpotato"

    /// False when the store fell back to local-only (unsigned builds, no entitlement).
    let isCloudBacked: Bool
    let setupError: String?
    private(set) var account: Account = .unknown
    private(set) var lastSync: Date?
    /// Changes the moment another device's edits land, so the UI can merge duplicates.
    private(set) var lastImport: Date?
    private(set) var lastError: String?
    private var inFlight = Set<UUID>()

    var isSyncing: Bool { !inFlight.isEmpty }

    /// Whether this build is signed with the CloudKit entitlement. CloudKit APIs trap
    /// without it, which is the case for unsigned simulator and test builds.
    nonisolated static var hasCloudKitEntitlement: Bool {
        #if targetEnvironment(simulator)
        // Signed simulator builds carry their entitlements in a __TEXT,__entitlements section.
        guard let header = _dyld_get_image_header(0) else { return false }
        var size: UInt = 0
        let data = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) {
            getsectiondata($0, "__TEXT", "__entitlements", &size)
        }
        guard let data, size > 0 else { return false }
        return String(decoding: UnsafeBufferPointer(start: data, count: Int(size)), as: UTF8.self)
            .contains("com.apple.developer.icloud-services")
        #elseif os(iOS)
        return true // Device builds are always signed; ours always carry the entitlement.
        #else
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) != nil
        #endif
    }

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(isCloudBacked: Bool, setupError: String?) {
        self.isCloudBacked = isCloudBacked
        self.setupError = setupError
        guard isCloudBacked else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated { self?.handle(event) }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refreshAccount() }
        })
        Task { await refreshAccount() }
    }

    func refreshAccount() async {
        guard isCloudBacked else { return }
        let status = try? await CKContainer(identifier: Self.containerID).accountStatus()
        account = switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .unavailable
        default: .unknown
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        guard let end = event.endDate else {
            inFlight.insert(event.identifier)
            return
        }
        inFlight.remove(event.identifier)
        let kind = switch event.type {
        case .setup: "setup"
        case .import: "import"
        case .export: "export"
        @unknown default: "event"
        }
        if event.succeeded {
            lastSync = end
            lastError = nil
            if event.type == .import { lastImport = end }
            print("[Sync] \(kind) succeeded")
        } else if let error = event.error {
            lastError = Self.describe(error)
            print("[Sync] \(kind) failed: \(error)")
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        switch ck.code {
        case .notAuthenticated: return "Sign in to iCloud to sync."
        case .quotaExceeded: return "Your iCloud storage is full."
        case .networkUnavailable, .networkFailure: return "Offline. Changes will sync when you're back online."
        case .accountTemporarilyUnavailable: return "iCloud is temporarily unavailable."
        default: return ck.localizedDescription
        }
    }

    /// One-line status for Settings.
    var status: (title: String, detail: String?, symbol: String, healthy: Bool) {
        if !isCloudBacked {
            return ("Not syncing", setupError ?? "This build isn't signed for iCloud, so your library stays on this device.",
                    "icloud.slash", false)
        }
        switch account {
        case .noAccount:
            return ("Signed out of iCloud", "Sign in to iCloud in Settings to sync your library.", "icloud.slash", false)
        case .restricted:
            return ("iCloud restricted", "iCloud is restricted on this device.", "icloud.slash", false)
        case .unavailable:
            return ("iCloud unavailable", "Sync will resume when iCloud is available.", "exclamationmark.icloud", false)
        case .unknown, .available:
            break
        }
        if let lastError { return ("Sync problem", lastError, "exclamationmark.icloud", false) }
        if isSyncing { return ("Syncing…", nil, "arrow.triangle.2.circlepath.icloud", true) }
        if let lastSync {
            return ("Up to date", "Last synced \(lastSync.formatted(.relative(presentation: .named)))", "checkmark.icloud", true)
        }
        return ("Waiting to sync", "Changes sync automatically in the background.", "icloud", true)
    }
}
