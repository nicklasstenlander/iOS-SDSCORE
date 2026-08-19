import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var cogWork: CogWorkService
    @StateObject private var contentCards = ContentCardsService()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let onShowAllCourses: () -> Void
    let onShowSchedule: () -> Void
    let onOpenCourse: (Event) -> Void
    let onOpenCourseID: (Int) -> Void
    @State private var bookingURL: URL?
    @State private var showSafari = false

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
    }

    private let levels: [(name: String, description: String)] = [
        ("Nivå 1", "För dig som aldrig dansat tidigare. Grundläggande teknik och rörelseglädje i ett tryggt tempo."),
        ("Nivå 2", "Dansat 1–2 terminer. Nya steg, kombinationer och rytmiska moment i ett lite snabbare tempo."),
        ("Nivå 3", "Dansat 2–3 terminer. Mer komplexa kombinationer, högre tempo och mer utmaning."),
        ("Nivå 4", "Dansat i några år. Tempot är högre och kombinationerna kräver förståelse. Nära avancerad nivå."),
        ("Advanced", "Dansat länge på hög nivå. Scenisk erfarenhet, eget rörelsespråk och uttryck."),
        ("Open Level", "Dansklasser för vuxna – oavsett nivå. Prova en ny stil eller njut av rörelsen.")
    ]

    private var featuredCourses: [Event] {
        let groups = ["Barndans", "K-pop", "Jazz", "Yoga", "Vuxna"]
        var selected: [Event] = []

        for group in groups {
            guard selected.count < 4,
                  let event = cogWork.events
                    .filter({ Periods.matches($0, period: cogWork.selectedPeriod) })
                    .sorted(by: { ($0.name ?? "") < ($1.name ?? "") })
                    .first(where: { $0.categoryName.localizedCaseInsensitiveContains(group) }) else {
                continue
            }
            if !selected.contains(where: { $0.id == event.id }) {
                selected.append(event)
            }
        }

        return selected
    }

    private var heroVideoTint: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heroSection

                if !contentCards.cards.isEmpty {
                    contentCardsSection
                        .padding(.horizontal, 20)
                }

                courseFinderSection
                    .padding(.horizontal, 20)

                levelsSection
                    .padding(.horizontal, 20)

                contactFooter
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .background(Color.sdsPublicBackground.ignoresSafeArea())
        .task {
            await contentCards.loadCardsIfNeeded()
            if cogWork.events.isEmpty {
                await cogWork.loadEvents()
            }
        }
        .sheet(isPresented: $showSafari) {
            if let bookingURL {
                SafariView(url: bookingURL).ignoresSafeArea()
            }
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            LoopingVideoView(filename: "Hero-film", fileExtension: "m4v")
                .frame(height: 390)
                .clipped()
                .overlay(heroVideoTint.opacity(0.16))
                .overlay(
                    LinearGradient(
                        colors: [heroVideoTint.opacity(0.12), .clear, heroVideoTint.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            heroTopBar

            Text("Kvalitet &\nDansglädje")
                .font(SDSType.agrandir(58, variant: .wideLight))
                .foregroundColor(.sdsAqua)
                .multilineTextAlignment(.center)
                .lineSpacing(0)
                .minimumScaleFactor(0.62)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 116)

            HeroWave()
                .fill(Color.sdsPublicBackground)
                .frame(height: 54)
        }
        .frame(height: 390)
    }

    private var heroTopBar: some View {
        VStack(spacing: 0) {
            HStack {
                BundleImage(filename: "SDS Dancer Three Lines Black", fileExtension: "png")
                    .scaledToFit()
                    .frame(width: 184)
                    .modifier(InvertInDarkMode(active: colorScheme == .dark))
                    .accessibilityLabel("Sollentuna Dans & Scenskola")

                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(height: 86)
            .background(Color.adaptive(light: "ffffff", dark: "0d0d0d").opacity(0.92))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.sdsBorder)
                    .frame(height: 1)
            }

            Spacer()
        }
    }

    private var contentCardsSection: some View {
        Group {
            if isWideLayout {
                iPadNewsSection(cards: contentCards.cards)
            } else {
                iPhoneNewsSection
            }
        }
    }

    private var iPhoneNewsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(contentCards.cards) { card in
                ContentCardView(card: card) {
                    handleCardTap(card)
                }
            }
        }
    }

    @ViewBuilder
    private func iPadNewsSection(cards: [ContentCard]) -> some View {
        let slots = buildCardLayout(from: cards)
        let rows = buildCardRows(from: slots)
        VStack(spacing: 16) {
            ForEach(rows.indices, id: \.self) { i in
                cardRow(rows[i])
            }
        }
    }

    @ViewBuilder
    private func cardRow(_ row: CardRow) -> some View {
        switch row {
        case .pair(let left, let right):
            HStack(spacing: 16) {
                ContentCardView(card: left.card) { handleCardTap(left.card) }
                    .frame(maxWidth: .infinity)
                ContentCardView(card: right.card) { handleCardTap(right.card) }
                    .frame(maxWidth: .infinity)
            }
        case .single(let slot):
            ContentCardView(card: slot.card) { handleCardTap(slot.card) }
                .frame(maxWidth: .infinity)
        }
    }

    private func handleCardTap(_ card: ContentCard) {
        guard let destination = card.appDestination?.trimmingCharacters(in: .whitespacesAndNewlines),
              !destination.isEmpty else {
            if let urlString = card.linkUrl, let url = URL(string: urlString) {
                bookingURL = url
                showSafari = true
            }
            return
        }

        if destination == "kurser" {
            onShowAllCourses()
        } else if destination == "schema" {
            onShowSchedule()
        } else if destination.hasPrefix("course:") {
            let eventIdString = destination.replacingOccurrences(of: "course:", with: "")
            if let eventId = Int(eventIdString) {
                onOpenCourseID(eventId)
            } else {
                onShowAllCourses()
            }
        }
    }

    private var courseFinderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Från första steg till full passion.")
                    .font(SDSType.agrandir(25, weight: .bold))
                    .foregroundColor(.sdsTeal)
                Text("Våra kurser passar både dig som är helt ny och dig som dansat länge.")
                    .font(SDSType.agrandir(15))
                    .foregroundColor(.sdsSecondaryText)
            }

            if featuredCourses.isEmpty {
                ProgressView()
                    .tint(.sdsDarkGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(featuredCourses) { event in
                            FeaturedCourseCard(event: event) {
                                onOpenCourse(event)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                onShowAllCourses()
            } label: {
                Label("Se alla kurser", systemImage: "arrow.right.circle")
                    .font(SDSType.agrandir(16, weight: .bold))
                    .foregroundColor(.sdsTeal)
            }
        }
    }

    private var levelsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hitta din nivå")
                .font(SDSType.agrandir(25, weight: .bold))
                .foregroundColor(.sdsTeal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(levels, id: \.name) { level in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(level.name)
                                .font(SDSType.agrandir(17, weight: .bold))
                                .foregroundColor(.sdsTeal)
                            Text(level.description)
                                .font(SDSType.agrandir(14))
                                .foregroundColor(.sdsSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: 230, alignment: .topLeading)
                        .frame(minHeight: 150, alignment: .topLeading)
                        .padding(16)
                        .background(Color.sdsCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sdsBorder, lineWidth: 1))
                    }
                }
            }
        }
    }

    private var contactFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kontakt")
                .font(SDSType.agrandir(21, weight: .bold))
                .foregroundColor(.sdsTeal)

            Label("Kuskvägen 6, 191 62 Sollentuna", systemImage: "mappin")
            Link(destination: URL(string: "mailto:info@sollentunadansochscenskola.se")!) {
                Label("info@sollentunadansochscenskola.se", systemImage: "envelope")
            }
            Link(destination: URL(string: "tel:0850278989")!) {
                Label("08-502 78 989", systemImage: "phone")
            }
            Text("Telefontid vardagar 10:00–13:00")
            Text("Mån–Fre 15:30–21:30\nLör 9:00–14:00\nSön 9:00–13:00")
            Text("© 2026 Moon Movements AB")
                .foregroundColor(.sdsMutedText)
                .padding(.top, 4)
        }
        .font(SDSType.agrandir(14))
        .foregroundColor(.sdsPrimaryText)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sdsCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sdsBorder, lineWidth: 1))
    }
}

private struct ContentCardView: View {
    let card: ContentCard
    let onTap: () -> Void

    @ViewBuilder
    private func cardImage(_ card: ContentCard) -> some View {
        if let urlString = card.imageUrl, !urlString.isEmpty, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.sdsLightGreen
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var showsLinkButton: Bool {
        guard let label = card.linkLabel, !label.isEmpty else { return false }
        if let destination = card.appDestination?.trimmingCharacters(in: .whitespacesAndNewlines),
           !destination.isEmpty {
            return true
        }
        return card.linkUrl.flatMap(URL.init(string:)) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardImage(card)

            Text(card.title)
                .font(SDSType.agrandir(card.type == "banner" ? 21 : 18, weight: .bold))
                .foregroundColor(card.type == "banner" ? .white : .sdsTeal)

            if let body = card.body, !body.isEmpty {
                Text(body)
                    .font(SDSType.agrandir(14))
                    .foregroundColor(card.type == "banner" ? .white.opacity(0.88) : .sdsSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let label = card.linkLabel, showsLinkButton {
                Button {
                    onTap()
                } label: {
                    Label(label, systemImage: "arrow.up.right")
                        .font(SDSType.agrandir(14, weight: .bold))
                }
                .foregroundColor(card.type == "banner" ? .white : .sdsTeal)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.type == "banner" ? Color.sdsPink : Color.sdsCard)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(card.type == "banner" ? Color.clear : Color.sdsBorder, lineWidth: 1)
        )
    }
}

private struct FeaturedCourseCard: View {
    let event: Event
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(event.categoryName)
                .font(SDSType.agrandir(11, weight: .bold))
                .foregroundColor(.sdsTeal)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.sdsSubtleSurface)
                .clipShape(Capsule())

            Text(event.name ?? event.categoryName)
                .font(SDSType.agrandir(18, weight: .bold))
                .foregroundColor(.sdsPrimaryText)
                .lineLimit(2)

            Text(event.plainDescription ?? fallbackDescription)
                .font(SDSType.agrandir(14))
                .foregroundColor(.sdsSecondaryText)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: action) {
                Text("Läs mer →")
                    .font(SDSType.agrandir(14, weight: .bold))
                    .foregroundColor(.sdsTeal)
            }
        }
        .frame(width: 250, alignment: .topLeading)
        .frame(minHeight: 220, alignment: .topLeading)
        .padding(16)
        .background(Color.sdsCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sdsBorder, lineWidth: 1))
    }

    private var fallbackDescription: String {
        "En kurs med fokus på teknik, rörelseglädje och trygg utveckling i danssalen."
    }
}

private struct HeroWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.48))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.10),
            control1: CGPoint(x: rect.width * 0.34, y: rect.height * 0.95),
            control2: CGPoint(x: rect.width * 0.68, y: -rect.height * 0.16)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct BundleImage: View {
    let filename: String
    let fileExtension: String

    var body: some View {
        if let path = Bundle.main.path(forResource: filename, ofType: fileExtension),
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .resizable()
        } else {
            Color.clear
        }
    }
}

private struct InvertInDarkMode: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.colorInvert()
        } else {
            content
        }
    }
}

fileprivate enum CardLayoutSlot {
    case half(ContentCard)
    case full(ContentCard)

    var card: ContentCard {
        switch self {
        case .half(let c), .full(let c): return c
        }
    }
}

fileprivate enum CardRow {
    case pair(CardLayoutSlot, CardLayoutSlot)
    case single(CardLayoutSlot)
}

fileprivate func buildCardLayout(from cards: [ContentCard]) -> [CardLayoutSlot] {
    guard cards.count % 2 != 0 else {
        return cards.map { .half($0) }
    }

    var workingCards = cards

    if let lastCard = workingCards.last,
       lastCard.imageUrl == nil || lastCard.imageUrl?.isEmpty == true {
        return buildSlots(from: workingCards, fullWidthIndex: workingCards.count - 1)
    }

    if let indexWithoutImage = workingCards.lastIndex(where: {
        $0.imageUrl == nil || $0.imageUrl?.isEmpty == true
    }) {
        let card = workingCards.remove(at: indexWithoutImage)
        workingCards.append(card)
        return buildSlots(from: workingCards, fullWidthIndex: workingCards.count - 1)
    }

    return workingCards.map { .half($0) }
}

fileprivate func buildSlots(from cards: [ContentCard], fullWidthIndex: Int) -> [CardLayoutSlot] {
    cards.enumerated().map { index, card in
        index == fullWidthIndex ? .full(card) : .half(card)
    }
}

fileprivate func buildCardRows(from slots: [CardLayoutSlot]) -> [CardRow] {
    var rows: [CardRow] = []
    var i = 0
    while i < slots.count {
        switch slots[i] {
        case .full:
            rows.append(.single(slots[i]))
            i += 1
        case .half:
            if i + 1 < slots.count, case .half = slots[i + 1] {
                rows.append(.pair(slots[i], slots[i + 1]))
                i += 2
            } else {
                rows.append(.single(slots[i]))
                i += 1
            }
        }
    }
    return rows
}

#Preview {
    HomeView(
        onShowAllCourses: {},
        onShowSchedule: {},
        onOpenCourse: { _ in },
        onOpenCourseID: { _ in }
    )
    .environmentObject(CogWorkService())
}
