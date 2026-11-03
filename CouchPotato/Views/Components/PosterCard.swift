import SwiftUI
import SwiftData

/// A tilt-on-hover poster with a saved-status sticker.
struct PosterCard: View {
    var title: CatalogTitle
    var width: CGFloat = 130
    var showsCaption = true
    var status: WatchStatus?

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: title.posterURL, maxPixel: width * 3, placeholderTitle: title.name)
                .frame(width: width, height: width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let status {
                        Text(status.emoji)
                            .font(.system(size: 15))
                            .padding(5)
                            .background(.thinMaterial, in: Circle())
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let provider = title.providers.first, provider != .appleStore {
                        ProviderDot(provider: provider).padding(6)
                    }
                }
                .shadow(color: .black.opacity(hovering ? 0.3 : 0.15), radius: hovering ? 10 : 4, y: hovering ? 8 : 3)
                .rotationEffect(.degrees(hovering ? -1.5 : 0))
                .scaleEffect(hovering ? 1.04 : 1)

            if showsCaption {
                Text(title.name)
                    .font(Spud.display(13, weight: .bold))
                    .foregroundStyle(Spud.ink)
                    .lineLimit(1)
                Text(title.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Spud.inkSoft)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { hovering = h } }
        .accessibilityElement(children: .combine)
    }
}

/// A horizontally scrolling row of posters with a header.
struct PosterRow: View {
    var title: String
    var subtitle: String?
    var emoji: String?
    var titles: [CatalogTitle]
    var seeAll: Route?

    @Query private var saved: [SavedTitle]

    var body: some View {
        let statusByKey = Dictionary(saved.map { ($0.key, $0.status) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: title, subtitle: subtitle, emoji: emoji)
                if let seeAll {
                    NavigationLink(value: seeAll) {
                        Text("See all").font(.spudCaption).foregroundStyle(Spud.teal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(titles) { title in
                        NavigationLink(value: Route.detail(title)) {
                            PosterCard(title: title, status: statusByKey[title.ref.key])
                        }
                        .buttonStyle(.plain)
                        .titleContextMenu(title)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
    }
}

/// An adaptive grid of posters.
struct PosterGrid: View {
    var titles: [CatalogTitle]
    var minWidth: CGFloat = Device.isPhone ? 105 : 140

    @Query private var saved: [SavedTitle]

    var body: some View {
        let statusByKey = Dictionary(saved.map { ($0.key, $0.status) }, uniquingKeysWith: { a, _ in a })
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 14, alignment: .top)], spacing: 18) {
            ForEach(titles) { title in
                NavigationLink(value: Route.detail(title)) {
                    PosterCard(title: title, width: minWidth, status: statusByKey[title.ref.key])
                }
                .buttonStyle(.plain)
                .titleContextMenu(title)
            }
        }
        .padding(.horizontal)
    }
}

/// Quick actions on any poster: queue it, mark it watched, plan it.
struct TitleContextMenu: ViewModifier {
    var title: CatalogTitle
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.contextMenu {
            ForEach([WatchStatus.queued, .watching, .watched]) { status in
                Button {
                    Library.save(title, status: status, in: context)
                } label: {
                    Label(status.label, systemImage: status.symbol)
                }
            }
            Button {
                app.plan(title)
            } label: {
                Label("Plan a Couch Night…", systemImage: "calendar.badge.plus")
            }
            ShareLink(item: title.ref.webURL ?? title.ref.deepLink, subject: Text(title.name),
                      message: Text("Couch Potato says: watch \(title.name) 🥔"))
        }
    }
}

extension View {
    func titleContextMenu(_ title: CatalogTitle) -> some View { modifier(TitleContextMenu(title: title)) }
}
