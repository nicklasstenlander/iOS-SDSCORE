import SwiftUI

struct ContentCardsAdminView: View {
    @StateObject private var service = ContentCardsService()
    @State private var cards: [ContentCard] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cardPendingDeletion: ContentCard?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(SDSType.agrandir(13, weight: .bold))
                        .foregroundColor(.sdsPink)
                }
                .listRowBackground(Color.sdsPinkAdaptiveSurface)
            }

            Section {
                NavigationLink {
                    ContentCardEditorView(
                        card: nil,
                        onSaved: { newCard in upsertCard(newCard) },
                        onDeleted: { _ in }
                    )
                } label: {
                    Label("Skapa nytt kort", systemImage: "plus.circle.fill")
                        .font(SDSType.agrandir(16, weight: .bold))
                        .foregroundColor(.sdsDarkModeGreen)
                }
            }

            Section("Alla kort") {
                if isLoading && cards.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.sdsDarkModeGreen)
                        Text("Laddar kort...")
                            .font(SDSType.agrandir(14, weight: .bold))
                            .foregroundColor(.sdsSecondaryText)
                    }
                    .padding(.vertical, 8)
                } else if cards.isEmpty {
                    Text("Inga kort hittades")
                        .font(SDSType.agrandir(14))
                        .foregroundColor(.sdsSecondaryText)
                        .padding(.vertical, 8)
                } else {
                    ForEach(cards) { card in
                        NavigationLink {
                            ContentCardEditorView(
                                card: card,
                                onSaved: { updated in upsertCard(updated) },
                                onDeleted: { id in removeCard(id: id) }
                            )
                        } label: {
                            CardRowView(card: card)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                cardPendingDeletion = card
                            } label: {
                                Label("Radera", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .font(SDSType.agrandir(15))
        .navigationTitle("Nyheter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(isLoading)
                .foregroundColor(.sdsDarkModeGreen)
                .accessibilityLabel("Uppdatera kort")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "Radera kort?",
            isPresented: Binding(
                get: { cardPendingDeletion != nil },
                set: { if !$0 { cardPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Ja, radera permanent", role: .destructive) {
                if let card = cardPendingDeletion {
                    Task { await delete(card) }
                }
                cardPendingDeletion = nil
            }
            Button("Avbryt", role: .cancel) {
                cardPendingDeletion = nil
            }
        } message: {
            Text("Detta går inte att ångra.")
        }
        .scrollContentBackground(.hidden)
        .background(Color.sdsPageBackground)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            cards = try await service.fetchAllCards()
            errorMessage = nil
        } catch {
            errorMessage = "Kunde inte hämta kort."
        }
    }

    private func delete(_ card: ContentCard) async {
        do {
            try await service.deleteCard(id: card.id)
            cards.removeAll { $0.id == card.id }
            errorMessage = nil
        } catch {
            errorMessage = "Kunde inte radera kortet. Försök igen."
        }
    }

    private func upsertCard(_ card: ContentCard) {
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
        } else {
            cards.append(card)
            cards.sort { $0.sortOrder < $1.sortOrder }
        }
    }

    private func removeCard(id: String) {
        cards.removeAll { $0.id == id }
    }
}

private struct CardRowView: View {
    let card: ContentCard

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isActive ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(SDSType.agrandir(15, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
                    .lineLimit(1)

                Text("\(typeName) · \(statusText)")
                    .font(SDSType.agrandir(12))
                    .foregroundColor(.sdsSecondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private var isActive: Bool {
        guard card.published else { return false }
        let now = Date()
        guard let starts = parseDate(card.startsAt), starts <= now else { return false }
        if let expStr = card.expiresAt, let exp = parseDate(expStr) {
            return exp >= now
        }
        return true
    }

    private var typeName: String {
        switch card.type {
        case "news": "Nyhet"
        case "event": "Event"
        case "featured_course": "Utvald kurs"
        case "banner": "Banner"
        default: card.type
        }
    }

    private var statusText: String {
        guard card.published else { return "Utkast" }
        let now = Date()
        guard let starts = parseDate(card.startsAt) else { return "Publicerad" }
        if starts > now {
            return "Visas från \(formatDate(starts))"
        }
        if let expStr = card.expiresAt, let exp = parseDate(expStr) {
            if exp < now {
                return "Utgången sedan \(formatDate(exp))"
            }
            return "Visas t.o.m. \(formatDate(exp))"
        }
        return "Publicerad"
    }

    private func parseDate(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateStyle = .short
        return f.string(from: date)
    }
}
