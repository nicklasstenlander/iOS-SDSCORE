import SwiftUI

// MARK: - Age Group Filter

enum AgeGroupFilter: CaseIterable, Identifiable {
    case all, small, kids, tweens, adults

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Alla"
        case .small: "3–5 år"
        case .kids: "6–9 år"
        case .tweens: "10–14 år"
        case .adults: "Vuxna"
        }
    }

    func matches(_ event: Event) -> Bool {
        guard let min = event.requirements?.minAge else {
            return self == .all || self == .adults
        }
        switch self {
        case .all: return true
        case .small: return min <= 5
        case .kids: return min >= 6 && min <= 9
        case .tweens: return min >= 10 && min <= 14
        case .adults: return min >= 15
        }
    }
}

// MARK: - Course Catalog View

struct CourseCatalogView: View {
    enum Mode {
        case admin
        case `public`
    }

    @EnvironmentObject var cogWork: CogWorkService
    @State private var searchText = ""
    @State private var selectedAgeGroup = AgeGroupFilter.all
    @State private var selectedEvent: Event?
    @State private var selectedPublicTermID: String?
    let mode: Mode
    let initialSelectedEventID: Int?

    init(mode: Mode = .admin, initialSelectedEventID: Int? = nil) {
        self.mode = mode
        self.initialSelectedEventID = initialSelectedEventID
    }

    // Publikt läge: CogWork styr vad som visas (registration.showing), så katalogen innehåller bara
    // terminer som går att se/boka – t.ex. både HT26 och VT27 när VT27-anmälan öppnat. Admin följer selectedPeriod.
    private var catalogEvents: [Event] {
        guard mode == .public else {
            return cogWork.events.filter { Periods.matches($0, period: cogWork.selectedPeriod) }
        }
        guard let termID = activePublicTermID else { return cogWork.events }
        return cogWork.events.filter { $0.grouping?.eventBlock?.id?.stringValue == termID }
    }

    private var publicTerms: [(id: String, name: String)] {
        Periods.publicTerms(events: cogWork.events)
    }

    /// Valt terminsval, annars den senaste terminen med öppen anmälan (nästa termin så fort den öppnar).
    private var activePublicTermID: String? {
        if let selected = selectedPublicTermID, publicTerms.contains(where: { $0.id == selected }) {
            return selected
        }
        return Periods.defaultPublicTermID(events: cogWork.events)
    }

    private var filteredEvents: [Event] {
        var events = catalogEvents
        if selectedAgeGroup != .all {
            events = events.filter { selectedAgeGroup.matches($0) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return events }
        return events.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(query)
                || $0.categoryName.localizedCaseInsensitiveContains(query)
                || ($0.instructorsName ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedEvents: [(category: String, events: [Event])] {
        let grouped = Dictionary(grouping: filteredEvents) { $0.categoryName }
        return grouped
            .sorted {
                let rank0 = sectionRank(for: $0.key)
                let rank1 = sectionRank(for: $1.key)
                return rank0 != rank1 ? rank0 < rank1 : $0.key < $1.key
            }
            .map { (category: $0.key, events: $0.value.sorted(by: eventSortedBeforeInSection)) }
    }

    // Ordnar sektioner efter målgrupp: barn, unga, (okända kategorier som t.ex. dansstilar), vuxna, 60+ sist
    private func sectionRank(for category: String) -> Int {
        let lower = category.lowercased()
        if lower.contains("barn") || lower.contains("kids") { return 0 }
        if lower.contains("ung") || lower.contains("junior") || lower.contains("tonår") || lower.contains("teen") { return 1 }
        if lower.contains("vuxen") || lower.contains("vuxna") { return 3 }
        if lower.contains("60+") { return 4 }
        return 2
    }

    // Samma kursnamn inom en sektion sorteras efter veckodag + starttid, så "Jazz & Balett 55+" tis/tors inte blandas slumpmässigt
    private func eventSortedBeforeInSection(_ lhs: Event, _ rhs: Event) -> Bool {
        let nameL = lhs.name ?? ""
        let nameR = rhs.name ?? ""
        if nameL != nameR { return nameL < nameR }
        let keyL = lhs.scheduleSortKey
        let keyR = rhs.scheduleSortKey
        if keyL.0 != keyR.0 { return keyL.0 < keyR.0 }
        return keyL.1 < keyR.1
    }

    var body: some View {
        VStack(spacing: 0) {
            searchAndFilterBar
            contentArea
        }
        .background(Color.sdsPageBackground.ignoresSafeArea())
        .navigationTitle(mode == .public ? "Kurser" : "Kurskatalog")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEvent) { event in
            CourseCatalogDetailSheet(event: event, mode: mode)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            if cogWork.events.isEmpty {
                if mode == .public {
                    await cogWork.loadPublicCatalog()
                } else {
                    await cogWork.loadAllData()
                }
            }
            selectInitialEventIfNeeded()
        }
        .onAppear {
            selectInitialEventIfNeeded()
        }
        .onChange(of: initialSelectedEventID) { _, _ in
            selectInitialEventIfNeeded()
        }
        .onChange(of: cogWork.events.count) { _, _ in
            selectInitialEventIfNeeded()
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if cogWork.isLoadingEvents && catalogEvents.isEmpty {
            catalogEmptyState(icon: "arrow.down.circle", text: "Hämtar kurser...")
        } else if catalogEvents.isEmpty {
            catalogEmptyState(
                icon: "book.closed",
                text: mode == .public
                    ? "Kurserna laddas in så snart terminsutbudet är klart."
                    : "Kurskatalogen fylls när kurser är laddade för vald period."
            )
        } else if groupedEvents.isEmpty {
            catalogEmptyState(icon: "magnifyingglass", text: "Inga kurser matchar sökningen.")
        } else {
            // ScrollView + LazyVStack istället för List, eftersom insetGrouped-headers inte går att pinna;
            // kortutseendet per sektion (en sammanhängande rundad yta) återskapas manuellt.
            ScrollView {
                LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedEvents, id: \.category) { group in
                        Section {
                            VStack(spacing: 0) {
                                ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                                    Button {
                                        selectedEvent = event
                                    } label: {
                                        CatalogCourseRow(event: event, mode: mode)
                                            .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(.plain)

                                    if index < group.events.count - 1 {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .background(mode == .public ? Color.sdsPublicSubtleSurface : Color.sdsCard)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 16)
                        } header: {
                            sectionHeader(group.category)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SDSType.agrandir(14, weight: .semibold))
            .foregroundColor(.sdsSecondaryText)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.sdsPageBackground)
    }

    private func catalogEmptyState(icon: String, text: String) -> some View {
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

    private var searchAndFilterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(mode == .public ? .sdsTeal : .sdsAccent)
                TextField("Sök kurs, kategori eller lärare...", text: $searchText)
                    .font(SDSType.agrandir(14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.sdsTertiaryText)
                    }
                    .accessibilityLabel("Rensa sökning")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(mode == .public ? Color.sdsPublicSubtleSurface : Color.sdsSubtleSurface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(mode == .public ? Color.sdsPublicBorder : Color.sdsBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if mode == .public && publicTerms.count > 1 {
                Picker("Termin", selection: Binding(
                    get: { activePublicTermID ?? "" },
                    set: { selectedPublicTermID = $0 }
                )) {
                    ForEach(publicTerms, id: \.id) { term in
                        Text(term.name).tag(term.id)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AgeGroupFilter.allCases) { group in
                        Button {
                            selectedAgeGroup = group
                        } label: {
                            Text(group.title)
                                .font(SDSType.agrandir(13, weight: .bold))
                                .foregroundColor(selectedAgeGroup == group ? .white : filterAccentColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(selectedAgeGroup == group ? filterAccentColor : Color.clear)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(
                                        filterAccentColor,
                                        lineWidth: selectedAgeGroup == group ? 0 : 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
        .background(Color.sdsPageBackground)
    }

    private var filterAccentColor: Color {
        mode == .public ? .sdsTeal : .sdsAccent
    }

    private func selectInitialEventIfNeeded() {
        guard let initialSelectedEventID,
              selectedEvent?.id != initialSelectedEventID,
              let event = cogWork.events.first(where: { $0.id == initialSelectedEventID }) else {
            return
        }

        selectedEvent = event
    }
}

// MARK: - Course Row

private struct CatalogCourseRow: View {
    let event: Event
    let mode: CourseCatalogView.Mode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(event.name ?? "–")
                        .font(SDSType.agrandir(15, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)
                    if let age = event.ageRange {
                        CatalogAgePill(text: age, mode: mode)
                    }
                }
                HStack(spacing: 8) {
                    if let time = event.schedule?.dayAndTimeInfo {
                        Text(time)
                            .font(SDSType.agrandir(13, weight: .semibold))
                            .foregroundColor(.sdsPrimaryText)
                    }
                    if let place = event.place, !place.isEmpty {
                        Text("·")
                            .font(SDSType.agrandir(12))
                            .foregroundColor(.sdsTertiaryText)
                        Text(place)
                            .font(SDSType.agrandir(12))
                            .foregroundColor(.sdsSecondaryText)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let price = event.priceFormatted {
                    Text(price)
                        .font(SDSType.agrandir(14, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)
                }
                if mode == .admin {
                    if let accepted = event.statistics?.accepted,
                       let max = event.requirements?.maxParticipants {
                        Text(capacityText(accepted: accepted, max: max))
                            .font(SDSType.agrandir(12))
                            .foregroundColor(accepted > max ? .sdsPink : .sdsSecondaryText)
                    } else if let accepted = event.statistics?.accepted {
                        Text("\(accepted) anm.")
                            .font(SDSType.agrandir(12))
                            .foregroundColor(.sdsSecondaryText)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// Förklarar antalet istället för att bara visa en rosa siffra: "Överbokad +N", "Fullt" eller "accepterade/max"
private func capacityText(accepted: Int, max: Int) -> String {
    if accepted > max { return "Överbokad +\(accepted - max)" }
    if accepted == max { return "Fullt" }
    return "\(accepted)/\(max)"
}

private struct CatalogAgePill: View {
    let text: String
    let mode: CourseCatalogView.Mode

    var body: some View {
        Text(text)
            .font(SDSType.agrandir(11, weight: .bold))
            .foregroundColor(mode == .public ? .sdsDarkGreen : .sdsAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(mode == .public ? Color.sdsLightGreen : Color.sdsAccentSurface)
            .clipShape(Capsule())
    }
}

// MARK: - Detail Sheet

struct CourseCatalogDetailSheet: View {
    let event: Event
    let mode: CourseCatalogView.Mode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var push: PushNotificationService
    @State private var showBookingSafari = false

    private var bookingURL: URL? {
        URL(string: "https://dans.se/sollentunadans/shop/new?event=\(event.id)")
    }

    private var accentColor: Color {
        mode == .public ? .sdsTeal : .sdsAccent
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    infoSection
                    descriptionSection
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .background(Color.sdsPageBackground.ignoresSafeArea())
            .navigationTitle(event.name ?? "Kurs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    followButton
                }
            }
            .safeAreaInset(edge: .bottom) {
                if bookingURL != nil {
                    VStack(spacing: 0) {
                        Divider()
                        Button {
                            showBookingSafari = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Boka plats")
                                    .font(SDSType.agrandir(17, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        .background(Color.sdsPageBackground)
                    }
                }
            }
            .sheet(isPresented: $showBookingSafari) {
                if let url = bookingURL {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
        }
    }

    @ViewBuilder
    private var followButton: some View {
        let following = push.isFollowing(eventId: event.id)
        Button {
            Task {
                if !push.isRegistered && !push.permissionDenied {
                    await push.requestPermissionAndRegister()
                }
                if push.isRegistered {
                    await push.toggleFollowedEvent(id: event.id)
                }
            }
        } label: {
            Image(systemName: following ? "bell.fill" : "bell")
                .foregroundColor(following ? accentColor : .primary)
        }
        .accessibilityLabel(following ? "Sluta följa kursen" : "Följ kursen — få notiser")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(event.categoryName)
                    .font(SDSType.agrandir(12, weight: .bold))
                    .foregroundColor(mode == .public ? .sdsDarkGreen : .sdsAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(mode == .public ? Color.sdsLightGreen : Color.sdsAccentSurface)
                    .clipShape(Capsule())

                if let age = event.ageRange {
                    CatalogAgePill(text: age, mode: mode)
                }
            }

            Text(event.name ?? "–")
                .font(SDSType.agrandir(28, weight: .bold))
                .foregroundColor(.sdsPrimaryText)
        }
    }

    private var infoSection: some View {
        VStack(spacing: 0) {
            if let time = event.schedule?.dayAndTimeInfo {
                CatalogDetailRow(icon: "clock", label: "Tid", value: time, mode: mode)
                Divider().padding(.leading, 52)
            }
            if let place = event.place, !place.isEmpty {
                CatalogDetailRow(icon: "mappin.circle", label: "Sal", value: place, mode: mode)
                Divider().padding(.leading, 52)
            }
            if let instructor = event.instructorsName, !instructor.isEmpty {
                CatalogDetailRow(icon: "person", label: "Lärare", value: instructor, mode: mode)
                Divider().padding(.leading, 52)
            }
            if let price = event.priceFormatted {
                CatalogDetailRow(icon: "banknote", label: "Pris", value: price, mode: mode)
                Divider().padding(.leading, 52)
            }
            if let age = event.ageRange {
                CatalogDetailRow(icon: "figure.child", label: "Ålder", value: age, mode: mode)
                Divider().padding(.leading, 52)
            }
            if mode == .admin {
                occupancyRow
            }
        }
        .background(mode == .public ? Color.sdsPublicSubtleSurface : Color.sdsCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(mode == .public ? Color.sdsPublicBorder : Color.sdsBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var occupancyRow: some View {
        if let accepted = event.statistics?.accepted,
           let max = event.requirements?.maxParticipants {
            CatalogDetailRow(icon: "person.2", label: "Beläggning", value: "\(accepted) av \(max) platser", mode: mode)
        } else if let accepted = event.statistics?.accepted {
            CatalogDetailRow(icon: "person.2", label: "Anmälda", value: "\(accepted) deltagare", mode: mode)
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if let desc = event.plainDescription {
            VStack(alignment: .leading, spacing: 10) {
                Text("Kursbeskrivning")
                    .font(SDSType.agrandir(17, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)

                Text(desc)
                    .font(SDSType.agrandir(15))
                    .foregroundColor(.sdsSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sdsCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sdsBorder, lineWidth: 1))
        }
    }
}

private struct CatalogDetailRow: View {
    let icon: String
    let label: String
    let value: String
    let mode: CourseCatalogView.Mode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(mode == .public ? .sdsDarkModeGreen : .sdsAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(SDSType.agrandir(11, weight: .bold))
                    .foregroundColor(.sdsTertiaryText)
                    .textCase(.uppercase)
                Text(value)
                    .font(SDSType.agrandir(15))
                    .foregroundColor(.sdsPrimaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview("CourseCatalogView Public") {
    NavigationStack {
        CourseCatalogView(mode: .public)
    }
    .environmentObject(CogWorkService())
    .environmentObject(PushNotificationService.shared)
}

#Preview("CourseCatalogView Admin") {
    NavigationStack {
        CourseCatalogView()
    }
    .environmentObject(CogWorkService())
    .environmentObject(PushNotificationService.shared)
}
