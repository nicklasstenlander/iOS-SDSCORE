import SwiftUI
import SafariServices

struct PerformancesView: View {
    @EnvironmentObject private var rideau: RideauEventsService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let initialSelectedSlug: String?

    @State private var purchaseURL: URL?
    @State private var showSafari = false
    @State private var highlightedSlug: String?
    @State private var prewarmingToken: SFSafariViewController.PrewarmingToken?

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
    }

    private var sortedEvents: [RideauEvent] {
        rideau.events.sorted {
            (RideauISO8601.parse($0.startsAt) ?? .distantFuture) < (RideauISO8601.parse($1.startsAt) ?? .distantFuture)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .onAppear { scrollToInitialSelectionIfNeeded(proxy: proxy) }
            .onChange(of: initialSelectedSlug) { _, _ in scrollToInitialSelectionIfNeeded(proxy: proxy) }
            .onChange(of: rideau.events.count) { _, _ in scrollToInitialSelectionIfNeeded(proxy: proxy) }
        }
        .background(Color.sdsPageBackground.ignoresSafeArea())
        .navigationTitle("Föreställningar")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await rideau.loadIfNeeded(force: true)
        }
        .task {
            await rideau.loadIfNeeded()
            prewarmPurchaseConnections()
        }
        .onChange(of: rideau.events) { _, _ in
            prewarmPurchaseConnections()
        }
        .onDisappear {
            prewarmingToken?.invalidate()
            prewarmingToken = nil
        }
        .sheet(isPresented: $showSafari, onDismiss: {
            Task { await rideau.loadIfNeeded(force: true) }
        }) {
            if let purchaseURL {
                SafariView(url: purchaseURL).ignoresSafeArea()
            }
        }
    }

    /// biljetter.sollentunadansochscenskola.se får aldrig en första kontakt från
    /// appen innan SafariView öppnas — utan detta hänger SFSafariViewController
    /// ibland obestämt vit vid den allra första öppningen av en ny värd
    /// (bekräftat på riktig enhet; andra öppningen är alltid direkt eftersom
    /// anslutningen då redan är varm).
    private func prewarmPurchaseConnections() {
        prewarmingToken?.invalidate()
        let urls = sortedEvents.compactMap { URL(string: $0.purchaseUrl) }
        guard !urls.isEmpty else {
            prewarmingToken = nil
            return
        }
        prewarmingToken = SFSafariViewController.prewarmConnections(to: urls)
    }

    @ViewBuilder
    private var content: some View {
        if rideau.isLoading && rideau.events.isEmpty {
            emptyState(icon: "arrow.down.circle", text: "Hämtar föreställningar...")
        } else if rideau.errorMessage != nil && rideau.events.isEmpty {
            emptyState(icon: "exclamationmark.triangle", text: "Kunde inte hämta föreställningar. Dra nedåt för att försöka igen.")
        } else if sortedEvents.isEmpty {
            emptyState(icon: "ticket", text: "Inga kommande föreställningar just nu.")
        } else if isWideLayout {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(sortedEvents) { event in
                    card(for: event)
                }
            }
            .padding(16)
        } else {
            LazyVStack(spacing: 14) {
                ForEach(sortedEvents) { event in
                    card(for: event)
                }
            }
            .padding(16)
        }
    }

    private func card(for event: RideauEvent) -> some View {
        PerformanceCard(
            event: event,
            clockSkew: rideau.clockSkew,
            isHighlighted: highlightedSlug == event.slug,
            onBuy: {
                purchaseURL = URL(string: event.purchaseUrl)
                showSafari = true
            },
            onCountdownReachedZero: {
                Task { await rideau.loadIfNeeded(force: true) }
            }
        )
        .id(event.slug)
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.sdsMutedText)
            Text(text)
                .font(SDSType.agrandir(14))
                .foregroundColor(.sdsSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func scrollToInitialSelectionIfNeeded(proxy: ScrollViewProxy) {
        guard let initialSelectedSlug,
              sortedEvents.contains(where: { $0.slug == initialSelectedSlug }) else {
            return
        }

        highlightedSlug = initialSelectedSlug
        withAnimation {
            proxy.scrollTo(initialSelectedSlug, anchor: .top)
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            if highlightedSlug == initialSelectedSlug {
                highlightedSlug = nil
            }
        }
    }
}

private struct PerformanceCard: View {
    let event: RideauEvent
    let clockSkew: TimeInterval
    let isHighlighted: Bool
    let onBuy: () -> Void
    let onCountdownReachedZero: () -> Void

    @State private var hasTriggeredRefetchAtZero = false

    private var posterURL: URL? {
        event.posterUrl.flatMap(URL.init(string:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            posterImage

            Text(event.title)
                .font(SDSType.agrandir(18, weight: .bold))
                .foregroundColor(.sdsPrimaryText)

            if let dateText = RideauDateFormatting.displayText(for: event.startsAt) {
                HStack(spacing: 6) {
                    Text(dateText)
                    if let venue = event.venue, !venue.isEmpty {
                        Text("·")
                        Text(venue)
                    }
                }
                .font(SDSType.agrandir(13))
                .foregroundColor(.sdsSecondaryText)
            }

            priceSection
            statusSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sdsCard)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isHighlighted ? Color.sdsTeal : Color.sdsBorder, lineWidth: isHighlighted ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var posterImage: some View {
        Group {
            if let posterURL {
                AsyncImage(url: posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        posterPlaceholder
                    }
                }
            } else {
                posterPlaceholder
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .clipped()
    }

    private var posterPlaceholder: some View {
        ZStack {
            Color.sdsLightGreen
            Image(systemName: "ticket.fill")
                .font(.system(size: 28))
                .foregroundColor(.sdsDarkGreen.opacity(0.5))
        }
    }

    @ViewBuilder
    private var priceSection: some View {
        if let priceText = RideauPricing.priceText(for: event) {
            Text(priceText)
                .font(SDSType.agrandir(15, weight: .bold))
                .foregroundColor(.sdsPrimaryText)
        }
        if let lines = RideauPricing.freeTicketFallbackLines(for: event) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(SDSType.agrandir(13))
                    .foregroundColor(.sdsSecondaryText)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch event.salesState {
        case .soldOut:
            Text(RideauStatus.statusText(for: .soldOut) ?? "")
                .font(SDSType.agrandir(14, weight: .bold))
                .foregroundColor(.sdsPink)
        case .upcoming:
            if let salesOpenDate = event.salesOpenAt.flatMap(RideauISO8601.parse) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let text = RideauCountdown.text(salesOpenAt: salesOpenDate, now: context.date, clockSkew: clockSkew)
                    HStack {
                        if !text.isEmpty {
                            Text("Biljetterna släpps \(text)")
                                .font(SDSType.agrandir(13))
                                .foregroundColor(.sdsSecondaryText)
                        }
                        Spacer()
                        buyButton
                    }
                    .onChange(of: text) { _, newValue in
                        if newValue.isEmpty && !hasTriggeredRefetchAtZero {
                            hasTriggeredRefetchAtZero = true
                            onCountdownReachedZero()
                        }
                    }
                }
            } else {
                HStack { Spacer(); buyButton }
            }
        case .open:
            HStack { Spacer(); buyButton }
        case .unknown:
            EmptyView()
        }
    }

    @ViewBuilder
    private var buyButton: some View {
        if let title = RideauStatus.buttonTitle(for: event.salesState) {
            Button(action: onBuy) {
                Text(title)
                    .font(SDSType.agrandir(14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.sdsTeal)
                    .clipShape(Capsule())
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [event.title]
        if let spokenDate = RideauDateFormatting.spokenText(for: event.startsAt) {
            parts.append(spokenDate)
        }
        if let venue = event.venue, !venue.isEmpty {
            parts.append(venue)
        }
        if let spokenPrice = RideauPricing.spokenPriceText(for: event) {
            parts.append(spokenPrice)
        }
        if let buttonTitle = RideauStatus.buttonTitle(for: event.salesState) {
            parts.append(buttonTitle)
        } else if let statusText = RideauStatus.statusText(for: event.salesState) {
            parts.append(statusText)
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("PerformancesView") {
    NavigationStack {
        PerformancesView(initialSelectedSlug: nil)
    }
    .environmentObject(RideauEventsService())
}
