import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var cogWork: CogWorkService
    @StateObject private var contentCards = ContentCardsService()

    let onShowAllCourses: () -> Void
    let onOpenCourse: (Event) -> Void

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
            await contentCards.loadCards()
            if cogWork.events.isEmpty {
                await cogWork.loadEvents()
            }
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            LoopingVideoView(filename: "Hero-film", fileExtension: "m4v")
                .frame(height: 390)
                .clipped()
                .overlay(Color.white.opacity(0.16))
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.12), .clear, .white.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

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

    private var contentCardsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(contentCards.cards) { card in
                ContentCardView(card: card)
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
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if card.type == "event", let imageUrl = card.imageUrl, let url = URL(string: imageUrl) {
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

            Text(card.title)
                .font(SDSType.agrandir(card.type == "banner" ? 21 : 18, weight: .bold))
                .foregroundColor(card.type == "banner" ? .white : .sdsTeal)

            if let body = card.body, !body.isEmpty {
                Text(body)
                    .font(SDSType.agrandir(14))
                    .foregroundColor(card.type == "banner" ? .white.opacity(0.88) : .sdsSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let label = card.linkLabel, let linkUrl = card.linkUrl, let url = URL(string: linkUrl) {
                Button {
                    openURL(url)
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
