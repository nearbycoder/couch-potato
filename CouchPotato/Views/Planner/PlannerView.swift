import SwiftUI
import SwiftData

/// A week of planned viewing plus upcoming episodes of followed shows.
struct PlannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @Environment(AppModel.self) private var app
    @Environment(\.layout) private var layout
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
            VStack(alignment: .leading, spacing: 24) {
                weekStrip.padding(.horizontal, layout.margin)
                dayAgenda.padding(.horizontal, layout.margin)
                episodesSection.padding(.horizontal, layout.margin)
            }
            .padding(.vertical)
        }
        .appBackground()
        .navigationTitle("Planner")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { app.plan(nil) } label: { Label("Plan a Night", systemImage: "plus") }
            }
        }
        .task(id: followed.map(\.key).joined()) { await loadUpcoming() }
    }

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(weekTitle).font(.sectionTitle).foregroundStyle(Theme.textPrimary)
                if !Calendar.current.isDate(weekStart, equalTo: .now, toGranularity: .weekOfYear) {
                    Button("Today") {
                        weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
                        selectedDay = Calendar.current.startOfDay(for: .now)
                    }
                    .font(.seeAll)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
                Spacer()
                HStack(spacing: 4) {
                    Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous week")
                    Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next week")
                }
                .buttonStyle(.secondary)
            }

            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                    let isToday = Calendar.current.isDateInToday(day)
                    let count = nights(on: day).count
                    let episodeCount = episodes(on: day).count
                    Button {
                        withAnimation(.snappy) { selectedDay = day }
                    } label: {
                        VStack(spacing: 6) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text(day.formatted(.dateTime.day()))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(isSelected ? Theme.onAccent : (isToday ? Theme.accent : Theme.textPrimary))
                                .frame(width: 34, height: 34)
                                .background(isSelected ? Theme.accent : .clear, in: Circle())
                            HStack(spacing: 3) {
                                ForEach(0..<min(count, 3), id: \.self) { _ in Circle().fill(Theme.accent).frame(width: 4) }
                                ForEach(0..<min(episodeCount, 3), id: \.self) { _ in Circle().fill(Theme.info).frame(width: 4) }
                            }
                            .frame(height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(count) planned, \(episodeCount) episodes")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .card(padding: 8)
        }
    }

    private var dayAgenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: dayTitle, subtitle: selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            let todays = nights(on: selectedDay)
            let eps = episodes(on: selectedDay)
            if todays.isEmpty && eps.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundStyle(Theme.textTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nothing planned").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text("Pick something from your watchlist and set a time.").font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button("Plan") { app.plan(nil) }.buttonStyle(.secondary)
                }
                .card()
            } else {
                ForEach(todays) { night in NightCard(night: night) }
                ForEach(eps) { ep in EpisodeAgendaRow(episode: ep) }
            }
        }
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Coming Up",
                          subtitle: followed.isEmpty ? "Follow a series to see its new episodes here" : "New episodes from series you follow")
            if loadingEpisodes && upcoming.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if !followed.isEmpty && upcoming.isEmpty {
                Text("No upcoming episodes scheduled.").font(.subheadline).foregroundStyle(Theme.textSecondary)
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
        return selectedDay.formatted(.dateTime.weekday(.wide))
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
                .frame(width: 56, height: 84)
                .artwork(radius: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(night.titleName).font(.headline).foregroundStyle(Theme.textPrimary)
                    .strikethrough(night.isDone)
                Text("\(night.startsAt.formatted(date: .omitted, time: .shortened)) – \(night.endsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                if !night.note.isEmpty {
                    Text(night.note).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if night.remind { Pill(text: "Reminder", systemImage: "bell") }
                    if night.calendarEventID != nil { Pill(text: "Calendar", systemImage: "calendar") }
                }
            }
            Spacer(minLength: 0)
            Button {
                night.isDone.toggle()
                if night.isDone { Reminders.cancel(night) }
            } label: {
                Image(systemName: night.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(night.isDone ? Theme.success : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(night.isDone ? "Done" : "Mark as watched")
            .sensoryFeedback(.success, trigger: night.isDone)
        }
        .card()
        .contextMenu {
            if let ref = night.ref {
                Button("Open Title", systemImage: "info.circle") { app.open(ref) }
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
                    .artwork(radius: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.showName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("\(episode.code) · \(episode.name)").font(.footnote).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    if showsDate, let date = episode.airDate {
                        Text(date.formatted(.dateTime.weekday(.wide).month().day()) + " · " + date.formatted(.relative(presentation: .named)))
                            .font(.caption).foregroundStyle(Theme.info)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }
}

/// Sheet for scheduling a viewing night.
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
                Section("Title") {
                    if candidates.isEmpty {
                        Text("Add something to your watchlist first, then plan it here.").foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(candidates) { title in
                                    Button {
                                        pickedKey = title.ref.key
                                        if let runtime = title.runtime, runtime > 0 { duration = title.kind == .movie ? runtime + 15 : max(60, runtime * 2) }
                                    } label: {
                                        PosterCard(title: title, width: 84, showsCaption: false)
                                            .overlay(RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous)
                                                .strokeBorder(Theme.accent, lineWidth: pickedKey == title.ref.key ? 3 : 0))
                                            .opacity(pickedKey == nil || pickedKey == title.ref.key ? 1 : 0.5)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(title.name)
                                    .accessibilityAddTraits(pickedKey == title.ref.key ? .isSelected : [])
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        if let picked { Text(picked.name).font(.headline) }
                    }
                }
                Section("When") {
                    DatePicker("Starts", selection: $startsAt, in: Date.now.addingTimeInterval(-3600)...)
                    Stepper(value: $duration, in: 20...480, step: 10) {
                        LabeledContent("Length", value: duration.runtimeLabel)
                    }
                    // Wraps instead of scrolling so every shortcut is visible on narrow screens.
                    FlowLayout(spacing: 8) {
                        ForEach(quickTimes, id: \.0) { label, date in
                            Button(label) { startsAt = date }.buttonStyle(.bordered).tint(Theme.accent)
                        }
                    }
                }
                Section("Options") {
                    TextField("Note", text: $note, prompt: Text("Add a note"), axis: .vertical)
                    Toggle("Remind me \(prefs.remindMinutesBefore) minutes before", isOn: $remind)
                    Toggle("Add to Calendar", isOn: $addToCalendar)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Plan a Night")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
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
        if tonight > .now { list.append(("Tonight 8 PM", tonight)) }
        list.append(("Tomorrow 8 PM", tomorrow))
        list.append(("Saturday 7 PM", saturday))
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
