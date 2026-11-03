import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(Catalog.self) private var catalog
    @Environment(\.modelContext) private var context
    @Query private var saved: [SavedTitle]
    @Query private var nights: [CouchNight]

    @State private var keyDraft = ""
    @State private var keyStatus: KeyStatus = .idle
    @State private var iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil

    enum KeyStatus: Equatable { case idle, checking, ok, failed(String) }

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                RankCard(rank: CouchRank(titles: saved, nights: nights), saved: saved)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                TextField("Nickname", text: $prefs.nickname, prompt: Text("What should Spud call you?"))
            } header: {
                Text("You")
            }

            Section {
                FlowLayout(spacing: 8) {
                    ForEach(Provider.streamers) { provider in
                        Button {
                            withAnimation(.spring(response: 0.3)) { prefs.toggle(provider) }
                            catalog.reset()
                        } label: {
                            ProviderChip(provider: provider, isMine: prefs.isMine(provider))
                                .opacity(prefs.isMine(provider) ? 1 : 0.45)
                                .scaleEffect(prefs.isMine(provider) ? 1 : 0.95)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(prefs.isMine(provider) ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
                Toggle("Prefer my services in Mood Mash", isOn: $prefs.onlyMyServices)
                    .onChange(of: prefs.onlyMyServices) { catalog.reset() }
                Picker("Region", selection: $prefs.region) {
                    ForEach(Preferences.regions, id: \.code) { Text("\(flag($0.code)) \($0.name)").tag($0.code) }
                }
                .onChange(of: prefs.region) { catalog.reset() }
            } header: {
                Text("My streaming services")
            } footer: {
                Text("Spud highlights titles on services you already pay for and builds your home feed around them.")
            }

            Section {
                HStack {
                    Image(systemName: catalog.hasTMDB ? "checkmark.seal.fill" : "leaf.fill")
                        .foregroundStyle(catalog.hasTMDB ? Spud.lettuce : Spud.potato)
                    Text(catalog.hasTMDB ? "TMDB connected: every movie, series and service" : "Free mode: TVmaze series + Apple movie charts")
                }
                SecureField("TMDB API key or read token", text: $keyDraft)
                    .textContentType(.password)
                    .onSubmit { Task { await testKey() } }
                HStack {
                    Button("Save & test key") { Task { await testKey() } }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty || keyStatus == .checking)
                    if !prefs.tmdbKey.isEmpty {
                        Button("Remove key", role: .destructive) {
                            prefs.tmdbKey = ""
                            keyDraft = ""
                            keyStatus = .idle
                            catalog.reset()
                        }
                    }
                    Spacer()
                    switch keyStatus {
                    case .idle: EmptyView()
                    case .checking: ProgressView().controlSize(.small)
                    case .ok: Label("Works!", systemImage: "checkmark.circle.fill").foregroundStyle(Spud.lettuce)
                    case .failed(let message): Text(message).foregroundStyle(Spud.ketchup).font(.caption)
                    }
                }
                Link("Get a free TMDB key →", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
            } header: {
                Text("Data sources")
            } footer: {
                Text("The key syncs to your other devices through iCloud. Streaming availability is provided by JustWatch via TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB. Series data from TVmaze (CC BY-SA).")
            }

            Section {
                Toggle("Add new couch nights to Calendar", isOn: $prefs.addNightsToCalendar)
                Picker("Couch night reminder", selection: $prefs.remindMinutesBefore) {
                    Text("At start time").tag(0)
                    Text("5 minutes before").tag(5)
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                }
                Toggle("New episode alerts for followed shows", isOn: $prefs.newEpisodeAlerts)
                    .onChange(of: prefs.newEpisodeAlerts) { _, on in if on { Task { await Reminders.requestPermission() } } }
            } header: {
                Text("Planner")
            }

            Section {
                LabeledContent("iCloud") {
                    Label(iCloudAvailable ? "Syncing" : "Signed out", systemImage: iCloudAvailable ? "icloud.fill" : "icloud.slash")
                        .foregroundStyle(iCloudAvailable ? Spud.teal : Spud.inkSoft)
                }
                LabeledContent("Titles on your couch", value: "\(saved.count)")
                LabeledContent("Couch nights planned", value: "\(nights.count)")
                Button("Tidy up duplicates") { Library.dedupe(in: context) }
            } header: {
                Text("Sync")
            } footer: {
                Text("Your queue, ratings, progress and plans sync automatically between iPhone, iPad and Mac signed in to the same iCloud account.")
            }

            Section {
                Link("Couch Potato on GitHub", destination: URL(string: "https://github.com/nearbycoder/couch-potato")!)
                Link("Website", destination: URL(string: "https://nearbycoder.github.io/couch-potato/")!)
                Link("Privacy", destination: URL(string: "https://nearbycoder.github.io/couch-potato/privacy.html")!)
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            } header: {
                Text("About")
            } footer: {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        SpudMascot(size: 44, expression: .wink)
                        Text("Made with butter & SwiftUI").font(.spudCaption)
                    }
                    Spacer()
                }
                .padding(.top, 12)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .spudBackground()
        .navigationTitle("Settings")
        .onAppear { keyDraft = prefs.tmdbKey }
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

    private func flag(_ code: String) -> String {
        code.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }
}

struct RankCard: View {
    var rank: CouchRank
    var saved: [SavedTitle]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SpudMascot(size: 64, expression: rank.points > 50 ? .wink : .happy)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Couch Rank").font(.spudCaption).foregroundStyle(Color(hex: 0x3B2416).opacity(0.7))
                    Text("\(rank.level.emoji) \(rank.level.name)").font(Spud.display(24)).foregroundStyle(Color(hex: 0x3B2416))
                    Text(rank.level.quip).font(.system(size: 13, design: .rounded)).foregroundStyle(Color(hex: 0x3B2416).opacity(0.8))
                }
            }
            if let next = rank.nextLevel {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: rank.progressToNext).tint(Spud.ketchup)
                    Text("\(next.threshold - rank.points) pts to \(next.emoji) \(next.name)")
                        .font(.spudCaption).foregroundStyle(Color(hex: 0x3B2416).opacity(0.7))
                }
            }
            HStack {
                stat("\(rank.moviesWatched)", "movies")
                stat("\(rank.showsWatched)", "series")
                stat("\(rank.hoursWatched)h", "couch time")
                stat(avgRating, "avg 🥔")
            }
        }
        .padding(18)
        .background(LinearGradient(colors: [Spud.butter, Spud.potato], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var avgRating: String {
        let rated = saved.filter { $0.potatoes > 0 }
        guard !rated.isEmpty else { return "–" }
        return String(format: "%.1f", Double(rated.map(\.potatoes).reduce(0, +)) / Double(rated.count))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Spud.display(20)).foregroundStyle(Color(hex: 0x3B2416))
            Text(label).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Color(hex: 0x3B2416).opacity(0.7))
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
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            SpudMascot(size: 120, expression: page == 0 ? .wow : .happy)
            if page == 0 {
                VStack(spacing: 10) {
                    Text("Hi! I'm Spud 👋").font(Spud.display(32)).foregroundStyle(Spud.ink)
                    Text("I live on your couch and I know what's on every streaming service. Let's find you something great to watch.")
                        .font(.spudBody).foregroundStyle(Spud.inkSoft).multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                Button("Let's go!") { withAnimation(.spring) { page = 1 } }.buttonStyle(.chunky(Spud.ketchup))
            } else {
                VStack(spacing: 10) {
                    Text("Which services do you have?").font(Spud.display(26)).foregroundStyle(Spud.ink).multilineTextAlignment(.center)
                    Text("Tap all that apply. You can change these any time.").font(.spudBody).foregroundStyle(Spud.inkSoft)
                }
                FlowLayout(spacing: 10) {
                    ForEach(Provider.streamers) { provider in
                        Button { withAnimation(.spring(response: 0.3)) { prefs.toggle(provider) } } label: {
                            ProviderChip(provider: provider, isMine: prefs.isMine(provider))
                                .opacity(prefs.isMine(provider) ? 1 : 0.5)
                                .scaleEffect(prefs.isMine(provider) ? 1.06 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 460)
                Button(prefs.myServiceIDs.isEmpty ? "Skip for now" : "Fluff the cushions 🛋️") {
                    prefs.hasOnboarded = true
                    dismiss()
                }
                .buttonStyle(.chunky(Spud.teal))
            }
            Spacer(minLength: 10)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .spudBackground()
        #if os(macOS)
        .frame(width: 560, height: 600)
        #endif
        .interactiveDismissDisabled()
    }
}
