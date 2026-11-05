import SwiftUI

/// "Ask Couch Potato": a conversation with the on-device assistant, which can search,
/// check where to watch, update the watchlist and plan nights.
struct AskView: View {
    @Environment(\.layout) private var layout

    @State private var assistant = Assistant()
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let suggestions = [
        "What should I watch tonight?",
        "Find a cozy mystery series",
        "What's on my watchlist?",
        "Where can I watch Severance?",
        "Something funny under an hour",
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if assistant.messages.isEmpty { intro }
                    ForEach(assistant.messages) { message in
                        MessageRow(message: message, isStreaming: assistant.isResponding && message == assistant.messages.last)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: assistant.messages.last?.text) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .appBackground()
        .navigationTitle("Ask Couch Potato")
        .inlineTitle()
        .toolbar {
            if !assistant.messages.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button { assistant.reset() } label: { Label("New Conversation", systemImage: "square.and.pencil") }
                }
            }
        }
        .onDisappear { assistant.stop() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.accent)
                Text("What are you in the mood for?").font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text("Ask for recommendations, check where something streams, or have me update your watchlist and plan a night.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { assistant.send(suggestion) } label: {
                        Pill(text: suggestion, tint: Theme.fill, foreground: Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Label("Runs on this device with Apple Intelligence", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, layout.margin)
        .padding(.top, 8)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask anything about what to watch", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))
            Button {
                if assistant.isResponding { assistant.stop() } else { send() }
            } label: {
                Image(systemName: assistant.isResponding ? "stop.fill" : "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!assistant.isResponding && draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel(assistant.isResponding ? "Stop" : "Send")
        }
        .padding(.horizontal, layout.margin)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func send() {
        let text = draft
        draft = ""
        focused = false
        assistant.send(text)
    }
}

private struct MessageRow: View {
    var message: Assistant.Message
    var isStreaming: Bool
    @Environment(\.layout) private var layout

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, layout.margin)
        case .assistant:
            VStack(alignment: .leading, spacing: 12) {
                if message.text.isEmpty && isStreaming {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Thinking…").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, layout.margin)
                } else {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(message.isError ? Theme.textSecondary : Theme.textPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, layout.margin)
                }
                if !message.titles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(message.titles.prefix(10)) { title in
                                PosterLink(route: .detail(title)) { PosterCard(title: title, width: layout.isCompact ? 104 : 124) }
                                    .titleContextMenu(title)
                            }
                        }
                        .padding(.horizontal, layout.margin)
                    }
                }
            }
        }
    }
}

/// Entry point at the top of Browse, shown only when Apple Intelligence is available.
struct AskCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button { app.push(.ask) } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Couch Potato").font(.headline).foregroundStyle(Theme.textPrimary)
                    Text("Your on-device assistant for what to watch")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Chat with the assistant to find something to watch")
    }
}
