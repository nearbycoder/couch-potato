import SwiftUI
import SwiftData

/// Spud Planner: a week of couch nights plus upcoming episodes of followed shows.
struct PlannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @Environment(AppModel.self) private var app
    @Query(sort: \CouchNight.startsAt) private var nights: [CouchNight]
    @Query(filter: #Predicate<SavedTitle> { $0.isFollowing }) private var followed: [SavedTitle]

    @State private var weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var upcoming: [EpisodeInfo] = []
    @State private var loadingEpisodes = false

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                weekStrip.padding(.horizontal)
                dayAgenda.padding(.horizontal)
                episodesSection.padding(.horizontal)
            }
            .padding(.vertical)
        }
        .spudBackground()
        .navigationTitle("Spud Planner")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { app.plan(nil) } label: { Label("Plan a Couch Night", systemImage: "plus") }
            }
        }
        .task(id: followed.map(\.key).joined()) { await loadUpcoming() }
    }

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left.circle.fill").font(.title2) }
                    .accessibilityLabel("Previous week")
                Spacer()
                VStack(spacing: 2) {
                    Text(weekTitle).font(.spudHeadline).foregroundStyle(Spud.ink)
                    if !Calendar.current.isDate(weekStart, equalTo: .now, toGranularity: .weekOfYear) {
                        Button("Back to this week") {
                            weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
                            selectedDay = Calendar.current.startOfDay(for: .now)
                        }
                        .font(.spudCaption)
                    }
                }
                Spacer()
                Button { shiftWeek(1) } label: { Image(systemName: "chevron.right.circle.fill").font(.title2) }
                    .accessibilityLabel("Next week")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Spud.teal)

            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                    let count = nights(on: day).count
                    let episodeCount = episodes(on: day).count
                    Button {
                        withAnimation(.spring(response: 0.3)) { selectedDay = day }
                    } label: {
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 11, weight: .bold, design: .rounded))
                            Text(day.formatted(.dateTime.day())).font(Spud.display(20))
                            HStack(spacing: 2) {
                                ForEach(0..<min(count, 3), id: \.self) { _ in Circle().fill(Spud.ketchup).frame(width: 5) }
                                ForEach(0..<min(episodeCount, 3), id: \.self) { _ in Circle().fill(Spud.teal).frame(width: 5) }
                            }
                            .frame(height: 6)
                        }
                        .foregroundStyle(isSelected ? .white : Spud.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? Spud.brown : (Calendar.current.isDateInToday(day) ? Spud.butter.opacity(0.4) : Spud.card),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(count) couch nights, \(episodeCount) episodes")
                }
            }
        }
    }

    private var dayAgenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: dayTitle, subtitle: "Couch nights", emoji: "🛋️")
            let todays = nights(on: selectedDay)
            if todays.isEmpty {
                HStack(spacing: 14) {
                    SpudMascot(size: 56, expression: .sleepy, bobbing: false)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nothing planned. The couch is lonely.").font(.spudBody).foregroundStyle(Spud.inkSoft)
                        Button("Plan a couch night") { app.plan(nil) }.buttonStyle(.chunky(Spud.teal))
                    }
                }
                .spudCard()
            } else {
                ForEach(todays) { night in
                    NightCard(night: night)
                }
            }
            let eps = episodes(on: selectedDay)
            if !eps.isEmpty {
                ForEach(eps) { ep in EpisodeAgendaRow(episode: ep) }
            }
        }
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Coming up on shows you follow", subtitle: followed.isEmpty ? "Follow a series (🔔 on its page) to see new episodes here" : nil, emoji: "📅")
            if loadingEpisodes && upcoming.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if !followed.isEmpty && upcoming.isEmpty {
                Text("No new episodes on the horizon. Time to binge the backlog!").font(.spudBody).foregroundStyle(Spud.inkSoft)
            }
            ForEach(upcoming.prefix(20)) { ep in EpisodeAgendaRow(episode: ep, showsDate: true) }
        }
    }

    private func nights(on day: Date) -> [CouchNight] {
        nights.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: day) }
    }

    private func episodes(on day: Date) -> [EpisodeInfo] {
        upcoming.filter { $0.airDate.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }
    }

    private func shiftWeek(_ delta: Int) {
        weekStart = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: weekStart) ?? weekStart
        selectedDay = weekStart
    }

    private var weekTitle: String {
        guard let end = days.last else { return "" }
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(selectedDay) { return "Tonight" }
        if Calendar.current.isDateInTomorrow(selectedDay) { return "Tomorrow" }
        return selectedDay.formatted(.dateTime.weekday(.wide).month().day())
    }

    private func loadUpcoming() async {
        guard !followed.isEmpty else { upcoming = []; return }
        loadingEpisodes = true
        let shows = followed.map { ($0.ref, $0.name, $0.posterURL) }
        var all: [EpisodeInfo] = []
        await withTaskGroup(of: [EpisodeInfo].self) { group in
            for (ref, name, poster) in shows {
                group.addTask { await catalog.upcomingEpisodes(ref, showName: name, poster: poster) }
            }
            for await eps in group { all += eps.prefix(6) }
        }
        upcoming = all.sorted { ($0.airDate ?? .distantFuture) < ($1.airDate ?? .distantFuture) }
        loadingEpisodes = false
        if prefs.newEpisodeAlerts {
            for ep in upcoming.prefix(30) { await Reminders.scheduleNewEpisode(ep) }
        }
    }
}

struct NightCard: View {
    @Bindable var night: CouchNight
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 14) {
            RemoteImage(url: night.posterURL, maxPixel: 240, placeholderTitle: night.titleName)
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(night.titleName).font(Spud.display(17, weight: .bold)).foregroundStyle(Spud.ink)
                    .strikethrough(night.isDone)
                Text("\(night.startsAt.formatted(date: .omitted, time: .shortened)) – \(night.endsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.spudCaption).foregroundStyle(Spud.teal)
                if !night.note.isEmpty {
                    Text(night.note).font(.system(size: 12, design: .rounded)).foregroundStyle(Spud.inkSoft).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if night.remind { Pill(text: "Reminder", systemImage: "bell.fill") }
                    if night.calendarEventID != nil { Pill(text: "In Calendar", systemImage: "calendar") }
                }
            }
            Spacer(minLength: 0)
            Button {
                night.isDone.toggle()
                if night.isDone { Reminders.cancel(night) }
            } label: {
                Image(systemName: night.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(night.isDone ? Spud.lettuce : Spud.inkSoft.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(night.isDone ? "Done" : "Mark as watched")
            .sensoryFeedback(.success, trigger: night.isDone)
        }
        .spudCard()
        .contextMenu {
            if let ref = night.ref {
                Button("Open title", systemImage: "info.circle") { app.open(ref) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Reminders.cancel(night)
                context.delete(night)
            }
        }
    }
}

struct EpisodeAgendaRow: View {
    var episode: EpisodeInfo
    var showsDate = false

    var body: some View {
        NavigationLink(value: Route.title(episode.showRef, preview: nil)) {
            HStack(spacing: 12) {
                RemoteImage(url: episode.showPosterURL, maxPixel: 200, placeholderTitle: episode.showName)
                    .frame(width: 44, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.showName).font(Spud.display(15, weight: .bold)).foregroundStyle(Spud.ink)
                    Text("\(episode.code) · \(episode.name)").font(.system(size: 13, design: .rounded)).foregroundStyle(Spud.inkSoft).lineLimit(1)
                    if showsDate, let date = episode.airDate {
                        Text(date.formatted(.dateTime.weekday(.wide).month().day()) + " · " + date.formatted(.relative(presentation: .named)))
                            .font(.spudCaption).foregroundStyle(Spud.teal)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Spud.inkSoft)
            }
            .spudCard(Spud.teal.opacity(0.12), padding: 12)
        }
        .buttonStyle(.plain)
    }
}

/// Sheet for scheduling a couch night.
struct PlanNightSheet: View {
    var initialTitle: CatalogTitle?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Preferences.self) private var prefs
    @Query(sort: \SavedTitle.updatedAt, order: .reverse) private var saved: [SavedTitle]

    @State private var pickedKey: String?
    @State private var startsAt = PlanNightSheet.defaultStart()
    @State private var duration = 120
    @State private var note = ""
    @State private var remind = true
    @State private var addToCalendar = false
    @State private var saving = false

    private var candidates: [CatalogTitle] {
        var list = saved.filter { $0.status == .queued || $0.status == .watching }.map(\.asCatalogTitle)
        if let initialTitle, !list.contains(initialTitle) { list.insert(initialTitle, at: 0) }
        return list
    }

    private var picked: CatalogTitle? { candidates.first { $0.ref.key == pickedKey } }

    var body: some View {
        NavigationStack {
            Form {
                Section("What are we watching?") {
                    if candidates.isEmpty {
                        Text("Add something to your Couch Queue first — then plan it here.").foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(candidates) { title in
                                    Button {
                                        pickedKey = title.ref.key
                                        if let runtime = title.runtime, runtime > 0 { duration = title.kind == .movie ? runtime + 15 : max(60, runtime * 2) }
                                    } label: {
                                        PosterCard(title: title, width: 84, showsCaption: false)
                                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Spud.ketchup, lineWidth: pickedKey == title.ref.key ? 4 : 0))
                                            .opacity(pickedKey == nil || pickedKey == title.ref.key ? 1 : 0.5)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(title.name)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        if let picked { Text(picked.name).font(.spudHeadline) }
                    }
                }
                Section("When?") {
                    DatePicker("Starts", selection: $startsAt, in: Date.now.addingTimeInterval(-3600)...)
                    Stepper(value: $duration, in: 20...480, step: 10) {
                        LabeledContent("Length", value: duration.runtimeLabel)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(quickTimes, id: \.0) { label, date in
                                Button(label) { startsAt = date }.buttonStyle(.bordered).tint(Spud.teal)
                            }
                        }
                    }
                }
                Section("Extras") {
                    TextField("Snack plan, who's coming…", text: $note, axis: .vertical)
                    Toggle("Remind me \(prefs.remindMinutesBefore) min before", isOn: $remind)
                    Toggle("Add to Calendar", isOn: $addToCalendar)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Plan a Couch Night")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Plan it 🥔") { Task { await save() } }
                        .disabled(picked == nil || saving)
                }
            }
            .onAppear {
                pickedKey = initialTitle?.ref.key ?? candidates.first?.ref.key
                addToCalendar = prefs.addNightsToCalendar
                if let runtime = (initialTitle ?? candidates.first)?.runtime, runtime > 0 {
                    duration = (initialTitle ?? candidates.first)?.kind == .movie ? runtime + 15 : max(60, runtime * 2)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private var quickTimes: [(String, Date)] {
        let cal = Calendar.current
        let tonight = cal.date(bySettingHour: 20, minute: 0, second: 0, of: .now)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: tonight)!
        var saturday = cal.nextDate(after: .now, matching: DateComponents(hour: 19, weekday: 7), matchingPolicy: .nextTime)!
        if saturday < .now { saturday = cal.date(byAdding: .weekOfYear, value: 1, to: saturday)! }
        var list: [(String, Date)] = []
        if tonight > .now { list.append(("Tonight 8pm", tonight)) }
        list.append(("Tomorrow 8pm", tomorrow))
        list.append(("Saturday 7pm", saturday))
        return list
    }

    static func defaultStart() -> Date {
        let cal = Calendar.current
        let tonight = cal.date(bySettingHour: 20, minute: 0, second: 0, of: .now)!
        return tonight > .now ? tonight : cal.date(byAdding: .hour, value: 1, to: cal.date(bySetting: .minute, value: 0, of: .now)!)!
    }

    private func save() async {
        guard let picked else { return }
        saving = true
        if Library.saved(picked.ref.key, in: context) == nil { Library.save(picked, status: .queued, in: context) }
        let night = CouchNight(titleKey: picked.ref.key, titleName: picked.name, posterURL: picked.posterURL,
                               startsAt: startsAt, durationMinutes: duration, note: note, remind: remind)
        context.insert(night)
        try? context.save()
        if remind { await Reminders.schedule(night, minutesBefore: prefs.remindMinutesBefore) }
        if addToCalendar { night.calendarEventID = await CalendarBridge.add(night) }
        saving = false
        dismiss()
    }
}
