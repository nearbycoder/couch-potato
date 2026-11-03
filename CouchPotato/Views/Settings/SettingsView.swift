import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(Catalog.self) private var catalog
    @Environment(SyncMonitor.self) private var sync
    @Environment(Intelligence.self) private var intelligence
    @Environment(\.modelContext) private var context
    @Query private var saved: [SavedTitle]
    @Query private var nights: [CouchNight]

    @State private var keyDraft = ""
    @State private var keyStatus: KeyStatus = .idle
    @State private var exportDocument: BackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var transferMessage: String?

    enum KeyStatus: Equatable { case idle, checking, ok, failed(String) }

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                StatsCard(rank: CouchRank(titles: saved, nights: nights), saved: saved)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Profile") {
                TextField("Name", text: $prefs.nickname, prompt: Text("Your name"))
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 164), spacing: 8)], spacing: 8) {
                    ForEach(Provider.streamers) { provider in
                        Button {
                            withAnimation(.snappy) { prefs.toggle(provider) }
                            catalog.reset()
                        } label: {
                            ProviderChip(provider: provider, isSelected: prefs.isMine(provider))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(prefs.isMine(provider) ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                Toggle("Prefer my services in Moods", isOn: $prefs.onlyMyServices)
                    .onChange(of: prefs.onlyMyServices) { catalog.reset() }
                Picker("Region", selection: $prefs.region) {
                    ForEach(Preferences.regions, id: \.code) { Text($0.name).tag($0.code) }
                }
                .onChange(of: prefs.region) { catalog.reset() }
            } header: {
                Text("My Services")
            } footer: {
                Text("Titles on your services are highlighted, and Tonight is built around them.")
            }

            Section {
                HStack {
                    Image(systemName: catalog.hasTMDB ? "checkmark.seal.fill" : "info.circle")
                        .foregroundStyle(catalog.hasTMDB ? Theme.success : Theme.textSecondary)
                    Text(catalog.hasTMDB ? "TMDB connected: full catalog and all-provider availability" : "Basic mode: TVmaze series and Apple movie charts")
                }
                SecureField("TMDB API key or read access token", text: $keyDraft)
                    .textContentType(.password)
                    .onSubmit { Task { await testKey() } }
                HStack {
                    Button("Save and Test") { Task { await testKey() } }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty || keyStatus == .checking)
                    if !prefs.tmdbKey.isEmpty {
                        Button("Remove Key", role: .destructive) {
                            prefs.tmdbKey = ""
                            keyDraft = ""
                            keyStatus = .idle
                            catalog.reset()
                        }
                    }
                    Spacer(minLength: 0)
                    switch keyStatus {
                    case .idle, .failed: EmptyView()
                    case .checking: ProgressView().controlSize(.small)
                    case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success).accessibilityLabel("Connected")
                    }
                }
                .buttonStyle(.borderless)
                if case .failed(let message) = keyStatus {
                    Text(message).foregroundStyle(Theme.danger).font(.footnote)
                }
                Link("Get a free TMDB API key", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
            } header: {
                Text("Data Sources")
            } footer: {
                Text("The key syncs to your other devices through iCloud. Streaming availability is provided by JustWatch via TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB. Series data from TVmaze (CC BY-SA).")
            }

            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(intelligence.isAvailable ? Theme.accent : Theme.textSecondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(intelligence.isAvailable ? "Ready" : "Unavailable").font(.body.weight(.medium))
                        Text(intelligence.unavailableReason ?? "Ask Couch Potato and Shuffle's picks use the on-device model.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("Runs entirely on this device. Your requests are never sent to a server.")
            }

            Section("Planner") {
                Toggle("Add viewing nights to Calendar", isOn: $prefs.addNightsToCalendar)
                Picker("Reminder", selection: $prefs.remindMinutesBefore) {
                    Text("At start time").tag(0)
                    Text("5 minutes before").tag(5)
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                }
                Toggle("New episode alerts for followed series", isOn: $prefs.newEpisodeAlerts)
                    .onChange(of: prefs.newEpisodeAlerts) { _, on in if on { Task { await Reminders.requestPermission() } } }
            }

            Section {
                let status = sync.status
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: status.symbol)
                        .font(.title3)
                        .foregroundStyle(status.healthy ? Theme.success : Theme.textSecondary)
                        .symbolEffect(.pulse, isActive: sync.isSyncing)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.title).font(.body.weight(.medium))
                        if let detail = status.detail {
                            Text(detail).font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                LabeledContent("Titles", value: "\(saved.count)")
                LabeledContent("Planned nights", value: "\(nights.count)")
                Button("Merge Duplicates") { Library.dedupe(in: context) }
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text("Your watchlist, ratings, progress and plans sync automatically between every iPhone, iPad and Mac signed in to the same iCloud account.")
            }
            .task { await sync.refreshAccount() }

            Section {
                Button("Export Library…", systemImage: "square.and.arrow.up") {
                    do {
                        exportDocument = BackupDocument(data: try Backup.export(titles: saved, nights: nights))
                        isExporting = true
                    } catch {
                        transferMessage = "Couldn't export: \(error.localizedDescription)"
                    }
                }
                Button("Import Library…", systemImage: "square.and.arrow.down") { isImporting = true }
                if let transferMessage {
                    Text(transferMessage).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Android & Backups")
            } footer: {
                Text("Export a backup file to move your library to the Couch Potato Android app, or import one exported from Android. Importing merges: nothing is deleted, and newer changes win.")
            }
            .fileExporter(isPresented: $isExporting, document: exportDocument, contentType: .json,
                          defaultFilename: "Couch Potato Library") { result in
                if case .success = result { transferMessage = "Exported \(saved.count) titles and \(nights.count) plans." }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                importBackup(result)
            }

            Section {
                HStack(spacing: 12) {
                    BrandMark(size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Couch Potato").font(.headline)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Link("GitHub", destination: URL(string: "https://github.com/nearbycoder/couch-potato")!)
                Link("Website", destination: URL(string: "https://nearbycoder.github.io/couch-potato/")!)
                Link("Privacy", destination: URL(string: "https://nearbycoder.github.io/couch-potato/privacy.html")!)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Settings")
        .onAppear { keyDraft = prefs.tmdbKey }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let summary = try Backup.merge(try Data(contentsOf: url), into: context)
            Library.dedupe(in: context)
            transferMessage = summary.message
        } catch {
            transferMessage = "Couldn't import that file. Choose a backup exported from Couch Potato."
        }
    }

    private func testKey() async {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keyStatus = .checking
        do {
            try await TMDBClient(key: key, region: prefs.region).validate()
            prefs.tmdbKey = key
            catalog.reset()
            keyStatus = .ok
        } catch {
            keyStatus = .failed(error.localizedDescription)
        }
    }
}

struct StatsCard: View {
    var rank: CouchRank
    var saved: [SavedTitle]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Level").font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
                    Text(rank.level.name).font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    Text(rank.level.quip).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("\(rank.points) pts").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            if let next = rank.nextLevel {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: rank.progressToNext).tint(Theme.accent)
                    Text("\(next.threshold - rank.points) points to \(next.name)")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            HStack {
                stat("\(rank.moviesWatched)", "Movies")
                stat("\(rank.showsWatched)", "Series")
                stat("\(rank.hoursWatched)h", "Watched")
                stat(avgRating, "Avg rating")
            }
        }
        .card(padding: 18)
    }

    private var avgRating: String {
        let rated = saved.filter { $0.potatoes > 0 }
        guard !rated.isEmpty else { return "–" }
        return String(format: "%.1f", Double(rated.map(\.potatoes).reduce(0, +)) / Double(rated.count))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// First-launch welcome: pick your services.
struct OnboardingView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 10)
            if page == 0 {
                BrandMark(size: 96)
                VStack(spacing: 10) {
                    Text("Welcome to Couch Potato").font(.title.bold()).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                    Text("Find what to watch across every streaming service, keep one watchlist, and plan your nights in.")
                        .font(.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                Button("Continue") { withAnimation(.snappy) { page = 1 } }.buttonStyle(.primary)
            } else {
                VStack(spacing: 8) {
                    Text("Your services").font(.title.bold()).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                    Text("Select the services you subscribe to. You can change this any time in Settings.")
                        .font(.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 164), spacing: 8)], spacing: 8) {
                        ForEach(Provider.streamers) { provider in
                            Button { withAnimation(.snappy) { prefs.toggle(provider) } } label: {
                                ProviderChip(provider: provider, isSelected: prefs.isMine(provider))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(prefs.isMine(provider) ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: 560)
                }
                Button(prefs.myServiceIDs.isEmpty ? "Skip for now" : "Done") {
                    prefs.hasOnboarded = true
                    dismiss()
                }
                .buttonStyle(.primary)
            }
            Spacer(minLength: 10)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        #if os(macOS)
        .frame(width: 560, height: 620)
        #endif
        .interactiveDismissDisabled()
    }
}
