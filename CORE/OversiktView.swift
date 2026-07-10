import SwiftUI

struct OversiktView: View {
    @EnvironmentObject var auth: SupabaseAuthService
    @EnvironmentObject var cogWork: CogWorkService
    @EnvironmentObject var goals: GoalsService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var expandedCard: OverviewCardID?
    @State private var selectedCourse: CourseOverviewData?
    @State private var courseSort = CourseOverviewSort.attention
    @State private var courseSearchText = ""
    @State private var contentWidth: CGFloat = 0
    @State private var cachedCourseRows: [CourseOverviewData] = []
    @State private var isRefreshingCourseRows = false
    @State private var goalEditorMode: GoalEditorMode?

    private var periods: [Period] { Periods.available }

    private var periodBookings: [Booking] {
        cogWork.periodBookings
    }

    private var statisticalPeriodBookings: [Booking] {
        cogWork.statisticalPeriodBookings
    }

    private var bookingCountByParticipant: [String: Int] {
        CourseMetricsEngine.countBookingsByParticipant(cogWork.bookings, eventLookup: eventLookup)
    }

    private var courseChangesByParticipant: [String: ParticipantCourseChange] {
        CourseMetricsEngine.courseChangesByParticipant(
            bookings: cogWork.bookings,
            currentPeriodCode: cogWork.selectedPeriod.codePrefix,
            eventLookup: eventLookup
        )
    }

    private var eventLookup: [String: Event] {
        cogWork.events.reduce(into: [:]) { lookup, event in
            var keys = [String(event.id)]
            if let key = event.key, !key.isEmpty {
                keys.append(key)
            }
            for key in keys where lookup[key] == nil {
                lookup[key] = event
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                filters
                goalsSection
                overviewKPIs
                courseOverviewSection

                if let error = cogWork.errorMessage {
                    Text(error)
                        .font(SDSType.agrandir(13, weight: .bold))
                        .foregroundColor(.sdsPink)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.sdsPinkSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newValue in
                            contentWidth = newValue
                        }
                }
            )
        }
        .background(Color.sdsPageBackground.ignoresSafeArea())
        .refreshable {
            await cogWork.loadAllData()
        }
        .task {
            if cogWork.bookings.isEmpty {
                await cogWork.loadAllData()
            }
            if goals.goals.isEmpty {
                await goals.loadGoals()
            }
        }
        .task(id: cogWork.selectedPeriod) {
            await rebuildCourseRows()
        }
        .onChange(of: cogWork.lastUpdated) { _, _ in
            Task { await rebuildCourseRows() }
        }
        .onChange(of: cogWork.selectedPeriod) { _, _ in
            expandedCard = nil
            selectedCourse = nil
        }
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(course: course)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func rebuildCourseRows() async {
        isRefreshingCourseRows = true
        defer { isRefreshingCourseRows = false }

        let bookings = cogWork.bookings
        let events = cogWork.events
        let period = cogWork.selectedPeriod

        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }

        let rows = await Task.detached(priority: .userInitiated) {
            OversiktView.buildCourseRowsBackground(bookings: bookings, events: events, period: period)
        }.value

        guard !Task.isCancelled else { return }
        cachedCourseRows = rows
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(todayLabel)\(periodCode.isEmpty ? "" : " · \(periodCode)")")
                .font(SDSType.agrandir(12, weight: .bold))
                .foregroundColor(.adaptive(light: "009399", dark: "A0C4B9"))
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(greeting),")
                    .font(SDSType.agrandir(42, weight: .light))
                    .italic()
                    .foregroundColor(.sdsPrimaryText)
                Text("\(greetingName).")
                    .font(SDSType.agrandir(42, variant: .regular))
                    .foregroundColor(.sdsPrimaryText)
            }

            if cogWork.isLoading {
                ProgressView("Hämtar data...")
                    .font(SDSType.agrandir(15, weight: .bold))
                    .tint(.sdsDarkGreen)
            } else if !statLine.isEmpty {
                Text(statLine)
                    .font(SDSType.agrandir(14))
                    .foregroundColor(.sdsSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Image(colorScheme == .dark ? "SDSCircleLogoWhite" : "CoreCircleLogo")
                .resizable()
                .scaledToFit()
                .frame(width: horizontalSizeClass == .regular ? 82 : 58, height: horizontalSizeClass == .regular ? 82 : 58)
                .accessibilityLabel("Sollentuna Dans & Scenskola")
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Period")
                .font(SDSType.agrandir(12, weight: .bold))
                .foregroundColor(.sdsSecondaryText)

            SDSPeriodPicker(periods: periods, selectedPeriod: $cogWork.selectedPeriod)
        }
    }

    private var overviewKPIs: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Översikt")
                .font(SDSType.agrandir(22, weight: .bold))
                .foregroundColor(.sdsPrimaryText)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(overviewCards) { card in
                    WebKPICard(
                        title: card.title,
                        value: card.value,
                        subtitle: card.subtitle,
                        delta: card.delta,
                        icon: card.icon,
                        style: card.style,
                        isExpanded: expandedCard == card.id
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            expandedCard = expandedCard == card.id ? nil : card.id
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                }
            }

            if let selected = selectedOverviewCard {
                ExpandedKPICard(card: selected)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }

    private var selectedOverviewCard: OverviewCard? {
        overviewCards.first { $0.id == expandedCard }
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mål")
                    .font(SDSType.agrandir(22, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)

                Spacer()

                if goals.isLoading {
                    ProgressView()
                        .tint(.sdsDarkModeGreen)
                } else {
                    Button {
                        Task { await goals.loadGoals() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.sdsDarkModeGreen)
                    .accessibilityLabel("Uppdatera mål")
                }
            }

            if let errorMessage = goals.errorMessage {
                Text(errorMessage)
                    .font(SDSType.agrandir(13, weight: .bold))
                    .foregroundColor(.sdsPink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.sdsPinkAdaptiveSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                GeometryReader { proxy in
                    let cardWidth = max(260, proxy.size.width * 0.86)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(activeGoals) { goal in
                                Button {
                                    goalEditorMode = .edit(goal)
                                } label: {
                                    GoalProgressCard(goal: goal, currentValue: currentValue(for: goal))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Ändra mål \(goal.title)")
                                    .frame(width: cardWidth)
                                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                        content
                                            .scaleEffect(phase.isIdentity ? 1 : 0.96)
                                            .opacity(phase.isIdentity ? 1 : 0.82)
                                    }
                            }

                            Button {
                                goalEditorMode = .create
                            } label: {
                                AddGoalCard()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Skapa nytt mål")
                            .frame(width: cardWidth)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.96)
                                    .opacity(phase.isIdentity ? 1 : 0.82)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
                .frame(height: 274)
            }
        }
        .padding(.bottom, 20)
        .sheet(item: $goalEditorMode) { mode in
            GoalEditorSheet(mode: mode)
                .environmentObject(goals)
        }
    }

    private var courseOverviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Kursöversikt")
                            .font(SDSType.agrandir(22, weight: .bold))
                            .foregroundColor(.sdsPrimaryText)

                        if isRefreshingCourseRows {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.sdsDarkModeGreen)
                        }
                    }

                    if let updated = cogWork.lastUpdated {
                        Text("Uppdaterad \(updated, format: .dateTime.hour().minute())")
                            .font(SDSType.agrandir(11))
                            .foregroundColor(.sdsTertiaryText)
                    }
                }

                Spacer()

                Menu {
                    ForEach(CourseOverviewSort.allCases) { sort in
                        Button {
                            courseSort = sort
                        } label: {
                            if courseSort == sort {
                                Label(sort.title, systemImage: "checkmark")
                            } else {
                                Text(sort.title)
                            }
                        }
                    }
                } label: {
                    Label(courseSort.title, systemImage: "arrow.up.arrow.down")
                        .font(SDSType.agrandir(12, weight: .bold))
                        .foregroundColor(.sdsDarkModeGreen)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Color.sdsSurface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.sdsBorder, lineWidth: 1))
                }
            }

            courseSearchField

            let allRows = cachedCourseRows
            let filtered = filteredRows(from: allRows)
            let sorted = sortedRows(from: filtered)

            if allRows.isEmpty {
                EmptyOverviewSectionCard(
                    icon: "book.closed",
                    title: "Ingen kursdata",
                    message: "Kursöversikten fylls när det finns anmälningar i vald period."
                )
            } else if filtered.isEmpty {
                EmptyOverviewSectionCard(
                    icon: "magnifyingglass",
                    title: "Inga kurser matchar",
                    message: "Ändra sökningen eller rensa fältet för att visa alla kurser igen."
                )
            } else {
                LazyVGrid(columns: courseGridColumns, alignment: .leading, spacing: 12) {
                    ForEach(sorted) { row in
                        CourseOverviewRow(row: row) {
                            selectedCourse = row
                        }
                    }
                }
            }
        }
    }

    private var courseSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.sdsDarkModeGreen)

            TextField("Sök kurs...", text: $courseSearchText)
                .font(SDSType.agrandir(14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !courseSearchText.isEmpty {
                Button {
                    courseSearchText = ""
                    selectedCourse = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.sdsTertiaryText)
                }
                .accessibilityLabel("Rensa kurssökning")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.sdsSubtleSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var greetingName: String {
        auth.profile?.firstName ?? "Sollentuna"
    }

    private var gridColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var courseGridColumns: [GridItem] {
        let count = contentWidth >= 640 ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }
    

    private var goalColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "God morgon" }
        if hour < 17 { return "God dag" }
        return "God kväll"
    }

    private var newTodayCount: Int {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return statisticalPeriodBookings.filter { $0.created.hasPrefix(today) }.count
    }

    private var unpaidCount: Int {
        statisticalPeriodBookings.filter { $0.payment?.paid == false }.count
    }

    private var acceptedCount: Int {
        statisticalPeriodBookings.filter { $0.isAcceptedForOverview }.count
    }

    private var awaitingCount: Int {
        cogWork.pendingReviewCount
    }

    private var acceptedPercent: Int {
        guard !statisticalPeriodBookings.isEmpty else { return 0 }
        return Int((Double(acceptedCount) / Double(statisticalPeriodBookings.count) * 100).rounded())
    }

    private var uniqueCourseCount: Int {
        Set(statisticalPeriodBookings.compactMap { $0.event?.id.map(String.init) ?? $0.event?.name }).count
    }

    private var activeStudentCount: Int {
        let acceptedBookings = statisticalPeriodBookings.filter(\.isAcceptedForOverview)
        let canonicalKeys = CourseMetricsEngine.canonicalParticipantKeys(for: acceptedBookings)

        return Set(acceptedBookings.compactMap {
            CourseMetricsEngine.canonicalParticipantIdentifier(for: $0, lookup: canonicalKeys)
        }).count
    }

    private var paidCount: Int {
        statisticalPeriodBookings.filter { $0.payment?.paid == true }.count
    }

    private var unpaidAmount: Double {
        statisticalPeriodBookings
            .filter { $0.payment?.paid == false }
            .compactMap { $0.payment?.priceAgreed }
            .reduce(0, +)
    }

    private var receivedPercent: Int {
        guard totalInvoiced > 0 else { return 0 }
        return Int((totalReceived / totalInvoiced * 100).rounded())
    }

    private var totalInvoiced: Double {
        statisticalPeriodBookings
            .filter(\.isAcceptedForOverview)
            .compactMap { $0.payment?.priceAgreed }
            .reduce(0, +)
    }

    private var totalReceived: Double {
        statisticalPeriodBookings
            .filter { $0.payment?.paid == true }
            .compactMap { $0.payment?.amountPaid }
            .reduce(0, +)
    }

    private var statLine: String {
        var parts: [String] = []
        if newTodayCount > 0 { parts.append("\(newTodayCount) nya anmälningar idag") }
        if unpaidCount > 0 { parts.append("\(unpaidCount) fakturor väntar betalning") }
        return parts.joined(separator: ". ")
    }

    private var periodCode: String {
        cogWork.selectedPeriod.codePrefix ?? ""
    }

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: Date()).uppercased()
    }

    private func formatted(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "sv_SE")))
    }

    private func formattedCurrency(_ value: Double) -> String {
        Int(value).formatted(.number.locale(Locale(identifier: "sv_SE")))
    }

    private func revenueText(_ value: Double) -> String {
        value > 0 ? "\(Int(value / 1000)) tkr" : "—"
    }

    private var overviewCards: [OverviewCard] {
        [
            OverviewCard(
                id: .registered,
                title: "Anmälda",
                value: formatted(statisticalPeriodBookings.count),
                subtitle: "\(uniqueCourseCount) kurser",
                delta: newTodayCount > 0 ? "+\(newTodayCount) idag" : nil,
                icon: "person.2",
                style: .violet,
                detailTitle: "Anmälningar",
                detailRows: [
                    .init(label: "Totalt antal", value: formatted(statisticalPeriodBookings.count)),
                    .init(label: "Nya idag", value: formatted(newTodayCount)),
                    .init(label: "Unika kurser", value: formatted(uniqueCourseCount))
                ],
                bookingFilter: .all
            ),
            OverviewCard(
                id: .accepted,
                title: "Antagna",
                value: formatted(acceptedCount),
                subtitle: statisticalPeriodBookings.isEmpty ? "Ingen data" : "\(acceptedPercent)% av anmälda",
                icon: "person.crop.circle.badge.checkmark",
                style: .ok,
                detailTitle: "Antagna deltagare",
                detailRows: [
                    .init(label: "Antagna", value: formatted(acceptedCount)),
                    .init(label: "Andel", value: "\(acceptedPercent)%"),
                    .init(label: "Ej antagna/okänt", value: formatted(max(statisticalPeriodBookings.count - acceptedCount, 0)))
                ],
                bookingFilter: .accepted
            ),
            OverviewCard(
                id: .unpaid,
                title: "Ej betalda",
                value: formatted(unpaidCount),
                subtitle: unpaidCount > 0 ? "Kräver åtgärd" : "Alla betalda",
                icon: "creditcard",
                style: unpaidCount > 0 ? .critical : .ok,
                detailTitle: "Betalningar att följa upp",
                detailRows: [
                    .init(label: "Obetalda", value: formatted(unpaidCount)),
                    .init(label: "Betalda", value: formatted(paidCount)),
                    .init(label: "Utestående belopp", value: "\(formattedCurrency(unpaidAmount)) kr")
                ],
                bookingFilter: .unpaid
            ),
            OverviewCard(
                id: .awaiting,
                title: "Återkoppling",
                value: formatted(awaitingCount),
                subtitle: awaitingCount > 0 ? "\(awaitingCount) behöver manuell check" : "Inga ärenden",
                icon: "clock",
                style: awaitingCount > 0 ? .warning : .ok,
                detailTitle: "Väntar återkoppling",
                detailRows: [
                    .init(label: "Ärenden", value: formatted(awaitingCount)),
                    .init(label: "Period", value: cogWork.selectedPeriod.displayName),
                    .init(label: "Status", value: awaitingCount > 0 ? "Behöver åtgärd" : "Klart")
                ],
                bookingFilter: .pendingOrAwaiting
            ),
            OverviewCard(
                id: .courses,
                title: "Antal elever",
                value: formatted(activeStudentCount),
                subtitle: "unika med aktiv antagning",
                icon: "person.3",
                style: .sky,
                detailTitle: "Elevunderlag",
                detailRows: [
                    .init(label: "Unika elever", value: formatted(activeStudentCount)),
                    .init(label: "Aktiva antagningar", value: formatted(acceptedCount)),
                    .init(label: "Period", value: cogWork.selectedPeriod.displayName)
                ]
            ),
            OverviewCard(
                id: .occupancy,
                title: "Beläggning",
                value: cogWork.avgOccupancyPercent.map { "\($0)%" } ?? "—",
                subtitle: cogWork.avgOccupancyPercent != nil ? "av tillgängliga platser" : "kräver kursplatser",
                icon: "chart.line.uptrend.xyaxis",
                style: .emerald,
                detailTitle: "Beläggning",
                detailRows: [
                    .init(label: "Medelbeläggning", value: cogWork.avgOccupancyPercent.map { "\($0)%" } ?? "—"),
                    .init(label: "Period", value: cogWork.selectedPeriod.displayName),
                    .init(label: "Underlag", value: "Kurser + antagna")
                ]
            ),
            OverviewCard(
                id: .invoiced,
                title: "Aviserat",
                value: revenueText(totalInvoiced),
                subtitle: totalInvoiced > 0 ? "\(formattedCurrency(totalInvoiced)) kr" : "Ingen data",
                icon: "banknote",
                style: .emerald,
                detailTitle: "Aviserat belopp",
                detailRows: [
                    .init(label: "Aviserat", value: "\(formattedCurrency(totalInvoiced)) kr"),
                    .init(label: "Mottaget", value: "\(formattedCurrency(totalReceived)) kr"),
                    .init(label: "Mottaget aviserat", value: "\(receivedPercent)%")
                ]
            ),
            OverviewCard(
                id: .received,
                title: "Mottaget",
                value: revenueText(totalReceived),
                subtitle: totalReceived > 0 ? "\(formattedCurrency(totalReceived)) kr" : "Ingen data",
                icon: "banknote.fill",
                style: .dark,
                detailTitle: "Mottagna betalningar",
                detailRows: [
                    .init(label: "Mottaget", value: "\(formattedCurrency(totalReceived)) kr"),
                    .init(label: "Betalda bokningar", value: formatted(paidCount)),
                    .init(label: "Obetalda bokningar", value: formatted(unpaidCount))
                ]
            )
        ]
    }

    private var activeGoals: [Goal] {
        goals.goals
            .filter { $0.archived != 1 }
            .sorted { $0.deadline.localizedStandardCompare($1.deadline) == .orderedAscending }
    }

    private func currentValue(for goal: Goal) -> Double {
        let bookings = statisticalBookings(for: goal)
        switch goal.metric {
        case .bookingsCount:
            return Double(bookings.count)
        case .acceptedCount:
            return Double(bookings.filter { $0.isAcceptedForOverview }.count)
        case .revenue:
            return bookings
                .filter(\.isAcceptedForOverview)
                .compactMap { $0.payment?.priceAgreed }
                .reduce(0, +)
        case .occupancy:
            return 0
        case .newStudents:
            return Double(bookings.filter {
                CourseMetricsEngine.isNewStudentBooking($0, countByParticipant: bookingCountByParticipant)
            }.count)
        }
    }

    private func statisticalBookings(for goal: Goal) -> [Booking] {
        let lookup = eventLookup
        let all = cogWork.bookings.filter { CourseMetricsEngine.isStatisticalBooking($0, eventLookup: lookup) }

        if let eventBlockId = goal.eventBlockId, !eventBlockId.isEmpty {
            // Hitta perioden i den kända listan för att få kodprefix-fallback via Periods.matches
            if let period = Periods.available.first(where: { $0.eventBlockId == eventBlockId }) {
                return all.filter { Periods.matches($0, period: period) }
            }
            // Okänt block-id: matcha direkt
            return all.filter { $0.event?.grouping?.eventBlock?.id?.stringValue == eventBlockId }
        }
        if let eventKey = goal.eventKey, !eventKey.isEmpty {
            return all.filter {
                $0.event?.key == eventKey
                    || $0.event?.id.map(String.init) == eventKey
            }
        }
        return all
    }

    private var newStudentCount: Int {
        let counts = bookingCountByParticipant
        return statisticalPeriodBookings.filter {
            CourseMetricsEngine.isNewStudentBooking($0, countByParticipant: counts)
        }.count
    }

    private func filteredRows(from rows: [CourseOverviewData]) -> [CourseOverviewData] {
        let query = courseSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            row.name.localizedCaseInsensitiveContains(query)
                || row.meta.localizedCaseInsensitiveContains(query)
                || row.status.title.localizedCaseInsensitiveContains(query)
        }
    }

    private func sortedRows(from rows: [CourseOverviewData]) -> [CourseOverviewData] {
        switch courseSort {
        case .attention:
            return rows.sorted {
                if $0.unpaid == $1.unpaid { return $0.registered > $1.registered }
                return $0.unpaid > $1.unpaid
            }
        case .registered:
            return rows.sorted { $0.registered > $1.registered }
        case .occupancy:
            return rows.sorted { $0.occupancyPercent < $1.occupancyPercent }
        case .revenue:
            return rows.sorted { $0.revenue > $1.revenue }
        }
    }

}

private extension OversiktView {
    nonisolated static func buildCourseRowsBackground(
        bookings: [Booking],
        events: [Event],
        period: Period
    ) -> [CourseOverviewData] {
        let lookup: [String: Event] = events.reduce(into: [:]) { result, event in
            var keys = [String(event.id)]
            if let key = event.key, !key.isEmpty { keys.append(key) }
            for key in keys where result[key] == nil { result[key] = event }
        }
        let counts = CourseMetricsEngine.countBookingsByParticipant(bookings, eventLookup: lookup)
        let courseChanges = CourseMetricsEngine.courseChangesByParticipant(
            bookings: bookings,
            currentPeriodCode: period.codePrefix,
            eventLookup: lookup
        )
        let periodEvents = events
            .filter { Periods.matches($0, period: period) && CourseMetricsEngine.isStatisticalEvent($0) }
        let periodBookings = bookings.filter { Periods.matches($0, period: period) }
        let grouped = Dictionary(grouping: periodBookings) { booking in
            courseKey(for: booking, lookup: lookup)
        }

        let eventRows = periodEvents.map { event in
            let key = String(event.id)
            let group = grouped[key] ?? event.key.flatMap { grouped[$0] } ?? []
            return courseRow(key: key, event: event, bookings: group, counts: counts, courseChanges: courseChanges, lookup: lookup)
        }

        let eventKeys = Set(periodEvents.flatMap { event -> [String] in
            var keys = [String(event.id)]
            if let key = event.key, !key.isEmpty { keys.append(key) }
            return keys
        })
        let fallbackRows = grouped.compactMap { key, group -> CourseOverviewData? in
            guard !eventKeys.contains(key), !group.isEmpty else { return nil }
            return courseRow(key: key, event: nil, bookings: group, counts: counts, courseChanges: courseChanges, lookup: lookup)
        }

        return eventRows + fallbackRows
    }

    private nonisolated static func courseRow(
        key: String,
        event: Event?,
        bookings group: [Booking],
        counts: [String: Int],
        courseChanges: [String: ParticipantCourseChange],
        lookup: [String: Event]
    ) -> CourseOverviewData {
        let statistical = group.filter { CourseMetricsEngine.isStatisticalBooking($0, eventLookup: lookup) }
        let accepted = statistical.filter(\.isAcceptedForOverview).count
        let unpaid = statistical.filter { $0.payment?.paid == false }.count
        let revenue = statistical.filter(\.isAcceptedForOverview).compactMap { $0.payment?.priceAgreed }.reduce(0, +)
        let paid = statistical.filter { $0.payment?.paid == true }.count
        let maxParticipants = event?.requirements?.maxParticipants
        let pct = maxParticipants.map { capacity in
            capacity > 0 ? Int((Double(accepted) / Double(capacity) * 100).rounded()) : 0
        } ?? 0
        let participants = group
            .sorted { ($0.participant?.name ?? "") < ($1.participant?.name ?? "") }
            .map { booking in
                CourseParticipantData(
                    booking: booking,
                    isNewStudent: CourseMetricsEngine.isNewStudentBooking(booking, countByParticipant: counts),
                    courseChange: CourseMetricsEngine.courseChange(for: booking, changesByParticipant: courseChanges),
                    isTicketPurchase: CourseMetricsEngine.isPerformance(booking: booking, eventLookup: lookup)
                )
            }

        let status: CourseOverviewStatus
        if unpaid > 0 { status = .attention }
        else if statistical.isEmpty { status = .neutral }
        else if let maxParticipants, maxParticipants > 0 {
            let ratio = Double(accepted) / Double(maxParticipants)
            status = ratio >= 0.85 ? .strong : (ratio <= 0.45 ? .low : .neutral)
        }
        else {
            status = .neutral
        }

        return CourseOverviewData(
            id: key,
            name: event?.name ?? group.first?.event?.name ?? "Okänd kurs",
            meta: courseMeta(event: event, fallbackBooking: group.first),
            registered: statistical.count,
            accepted: accepted,
            capacity: maxParticipants,
            occupancyPercent: pct,
            revenue: revenue,
            unpaid: unpaid,
            paid: paid,
            participants: participants,
            status: status
        )
    }

    private nonisolated static func courseKey(for booking: Booking, lookup: [String: Event]) -> String {
        if let id = booking.event?.id {
            return String(id)
        }

        if let key = booking.event?.key, !key.isEmpty {
            return lookup[key].map { String($0.id) } ?? key
        }

        return booking.event?.name ?? booking.key
    }

    private nonisolated static func courseMeta(event: Event?, fallbackBooking: Booking?) -> String {
        if let event {
            let blockLabel = event.grouping?.eventBlock?.name.map(Periods.blockNameToFullLabel)
            let periodLabel = compactPeriodLabel(blockLabel)
            let startParts = [event.schedule?.start?.date, event.schedule?.start?.time]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
            return ([periodLabel] + (startParts.isEmpty ? [] : [startParts.joined(separator: " ")]))
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        guard let fallbackBooking else { return "" }
        let periodLabel = compactPeriodLabel(fallbackBooking.overviewPeriodLabel)
        let startParts = [fallbackBooking.event?.startDate, fallbackBooking.event?.startTime]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return ([periodLabel] + (startParts.isEmpty ? [] : [startParts.joined(separator: " ")]))
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private nonisolated static func compactPeriodLabel(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: "Höstterminen ", with: "HT")
            .replacingOccurrences(of: "Vårterminen ", with: "VT")
    }
}

private enum OverviewCardID: Hashable {
    case registered
    case accepted
    case unpaid
    case awaiting
    case courses
    case occupancy
    case invoiced
    case received
}

private enum BookingFilter {
    case all, accepted, unpaid, pendingOrAwaiting, invoicedWithAmount, paid, none

    nonisolated func apply(to bookings: [Booking]) -> [Booking] {
        let sorted = bookings.sorted { $0.created > $1.created }
        switch self {
        case .none: return []
        case .all: return sorted
        case .accepted: return sorted.filter(\.isAcceptedForOverview)
        case .unpaid: return sorted.filter { $0.payment?.paid == false }
        case .pendingOrAwaiting: return sorted.filter { $0.isPendingReviewForOverview || $0.isAwaitingResponseForOverview }
        case .invoicedWithAmount: return sorted.filter { $0.isAcceptedForOverview && $0.payment?.priceAgreed != nil }
        case .paid: return sorted.filter { $0.payment?.paid == true }
        }
    }
}

private struct OverviewCard: Identifiable {
    let id: OverviewCardID
    let title: String
    let value: String
    var subtitle: String?
    var delta: String?
    let icon: String
    let style: WebKPICard.Style
    let detailTitle: String
    let detailRows: [OverviewDetailRow]
    var bookingFilter: BookingFilter = .none
}

private struct OverviewDetailRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct WebKPICard: View {
    enum Style {
        case violet
        case ok
        case critical
        case warning
        case sky
        case emerald
        case dark
    }

    let title: String
    let value: String
    var subtitle: String?
    var delta: String?
    let icon: String
    let style: Style
    var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text(title)
                    .font(SDSType.agrandir(13, weight: .bold))
                    .foregroundColor(titleColor)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 30, height: 30)
                    .background(iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 6) {
                    Text(value)
                        .font(SDSType.agrandir(24, weight: .bold))
                        .foregroundColor(valueColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let delta {
                        Text(delta)
                            .font(SDSType.agrandir(11, weight: .bold))
                            .foregroundColor(deltaColor)
                            .lineLimit(1)
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(SDSType.agrandir(11))
                        .foregroundColor(valueColor.opacity(0.72))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            HStack {
                Text(isExpanded ? "Visar detaljer" : "Tryck för mer")
                    .font(SDSType.agrandir(10, weight: .bold))
                    .foregroundColor(valueColor.opacity(0.62))
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(valueColor.opacity(0.62))
            }
            .padding(.top, 7)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .padding(12)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isExpanded ? iconColor.opacity(0.46) : borderColor, lineWidth: isExpanded ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .scaleEffect(isExpanded ? 1.015 : 1)
    }

    private var background: Color {
        switch style {
        case .violet: .sdsVioletAdaptiveSurface
        case .ok: .sdsLightGreenSurface
        case .critical: .sdsPinkAdaptiveSurface
        case .warning: .sdsAmberAdaptiveSurface
        case .sky: .sdsSkyAdaptiveSurface
        case .emerald: .sdsLightGreenSurface
        case .dark: Color.adaptive(light: "1a2e2e", dark: "0f0f0f")
        }
    }

    private var borderColor: Color {
        switch style {
        case .critical: .sdsPink.opacity(0.3)
        case .warning: .sdsBorder
        case .dark: .sdsBorder
        default: .sdsBorder
        }
    }

    private var valueColor: Color {
        style == .dark ? .white : .sdsPrimaryText
    }

    private var titleColor: Color {
        switch style {
        case .dark: .white.opacity(0.88)
        case .warning: .sdsWarningText
        default: .sdsPrimaryText.opacity(0.72)
        }
    }

    private var iconColor: Color {
        switch style {
        case .critical: .sdsPink
        case .warning: .sdsWarningText
        case .dark: .white.opacity(0.82)
        default: .sdsDarkModeGreen
        }
    }

    private var deltaColor: Color {
        style == .dark ? .sdsMidGreen : .sdsDarkGreen
    }

    private var iconBackground: Color {
        .sdsIconBackground
    }
}

private struct ExpandedKPICard: View {
    @EnvironmentObject var cogWork: CogWorkService
    let card: OverviewCard
    @State private var loadedBookings: [Booking] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: card.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.sdsDarkModeGreen)
                    .frame(width: 42, height: 42)
                    .background(Color.sdsIconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.detailTitle)
                        .font(SDSType.agrandir(20, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)
                    Text("Detaljer för \(card.title.lowercased()) i vald period.")
                        .font(SDSType.agrandir(13))
                        .foregroundColor(.sdsSecondaryText)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(card.detailRows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .font(SDSType.agrandir(13))
                            .foregroundColor(.sdsSecondaryText)
                        Spacer(minLength: 12)
                        Text(row.value)
                            .font(SDSType.agrandir(15, weight: .bold))
                            .foregroundColor(.sdsPrimaryText)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 11)

                    if row.id != card.detailRows.last?.id {
                        Rectangle()
                            .fill(Color.sdsBorder)
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Color.sdsSubtleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if !loadedBookings.isEmpty {
                OverviewBookingList(bookings: loadedBookings)
            }
        }
        .padding(18)
        .background(Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task(id: card.id) {
            loadedBookings = card.bookingFilter.apply(to: cogWork.periodBookings)
        }
    }
}

private struct OverviewBookingList: View {
    @EnvironmentObject var cogWork: CogWorkService
    @State private var selectedCustomer: CogWorkUser?
    let bookings: [Booking]

    private var visibleBookings: [Booking] {
        Array(bookings.prefix(12))
    }

    private var ticketCount: Int {
        bookings.reduce(0) { $0 + CourseMetricsEngine.bookingTicketQuantity($1) }
    }

    private var eventLookup: [String: Event] {
        cogWork.events.reduce(into: [:]) { lookup, event in
            var keys = [String(event.id)]
            if let key = event.key, !key.isEmpty {
                keys.append(key)
            }
            for key in keys where lookup[key] == nil {
                lookup[key] = event
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Poster")
                    .font(SDSType.agrandir(13, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)

                Spacer()

                Text(summary)
                    .font(SDSType.agrandir(11, weight: .bold))
                    .foregroundColor(.sdsSecondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 8)

            ForEach(visibleBookings) { booking in
                OverviewBookingRow(
                    booking: booking,
                    isTicketPurchase: CourseMetricsEngine.isPerformance(booking: booking, eventLookup: eventLookup)
                ) {
                    await openCustomer(for: booking)
                }

                if booking.id != visibleBookings.last?.id {
                    Rectangle()
                        .fill(Color.sdsBorder)
                        .frame(height: 1)
                        .padding(.leading, 56)
                }
            }

            if bookings.count > visibleBookings.count {
                Text("+ \(bookings.count - visibleBookings.count) fler poster")
                    .font(SDSType.agrandir(12, weight: .bold))
                    .foregroundColor(.sdsSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .background(Color.sdsSubtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .sheet(item: $selectedCustomer) { user in
            CustomerDetailSheet(user: user)
                .environmentObject(cogWork)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var summary: String {
        if ticketCount == bookings.count {
            return "\(bookings.count) personer"
        }
        return "\(ticketCount) biljetter · \(bookings.count) köp"
    }

    private func openCustomer(for booking: Booking) async {
        guard let name = booking.participant?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return }

        selectedCustomer = await cogWork.loadUser(named: name)
    }
}

private struct OverviewBookingRow: View {
    let booking: Booking
    let isTicketPurchase: Bool
    let openCustomer: () async -> Void

    private var ticketQuantity: Int {
        CourseMetricsEngine.bookingTicketQuantity(booking)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(Color.sdsTeal)
                .frame(width: 32, height: 32)
                .overlay(
                    Text(initials)
                        .font(SDSType.agrandir(11, weight: .bold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    Task { await openCustomer() }
                } label: {
                    Text(name)
                        .font(SDSType.agrandir(13, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                Text(booking.event?.name ?? "Okänd kurs")
                    .font(SDSType.agrandir(11))
                    .foregroundColor(.sdsSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if ticketQuantity > 1 {
                SDSBadge(text: "\(ticketQuantity) biljetter", color: .sdsSurface, textColor: .sdsSecondaryText)
            }

            if isTicketPurchase {
                SDSBadge(text: "Biljettköp", color: .sdsAmberAdaptiveSurface, textColor: .sdsWarningText)
            }

            PaymentStatusBadge(booking: booking)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var name: String {
        booking.participant?.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? booking.participant?.name ?? "Okänd deltagare"
            : "Okänd deltagare"
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        let value = (first + second).uppercased()
        return value.isEmpty ? "?" : value
    }
}

private struct PaymentStatusBadge: View {
    let booking: Booking

    var body: some View {
        if booking.payment?.paid == true {
            SDSBadge(text: paidText, color: .sdsLightGreenSurface, textColor: .sdsDarkModeGreen)
        } else if booking.payment?.paid == false {
            SDSBadge(text: unpaidText, color: .sdsPinkAdaptiveSurface, textColor: .sdsPink)
        }
    }

    private var paidText: String {
        let amount = booking.payment?.priceAgreed ?? booking.payment?.amountPaid
        guard let amount else { return "Betald" }
        return "Betald · \(Int(amount).formatted(.number.locale(Locale(identifier: "sv_SE")))) kr"
    }

    private var unpaidText: String {
        guard let due = booking.payment?.paymentDue, !due.isEmpty else { return "Obetald" }
        return "Obetald · \(String(due.prefix(10)))"
    }
}

private enum GoalEditorMode: Identifiable {
    case create
    case edit(Goal)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let goal):
            return "edit-\(goal.id)"
        }
    }

    var goal: Goal? {
        if case .edit(let goal) = self { return goal }
        return nil
    }

    var navigationTitle: String {
        goal == nil ? "Nytt mål" : "Ändra mål"
    }
}

private struct AddGoalCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.sdsDarkModeGreen)
                .frame(width: 72, height: 72)
                .background(Color.sdsLightGreenSurface)
                .clipShape(Circle())

            VStack(spacing: 5) {
                Text("Nytt mål")
                    .font(SDSType.agrandir(22, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)

                Text("Skapa ett nytt mål för översikten")
                    .font(SDSType.agrandir(13))
                    .foregroundColor(.sdsSecondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 202)
        .padding(20)
        .background(Color.sdsSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.sdsBorder, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

private struct GoalEditorSheet: View {
    @EnvironmentObject var goals: GoalsService
    @Environment(\.dismiss) private var dismiss

    let mode: GoalEditorMode

    @State private var title: String
    @State private var description: String
    @State private var metric: GoalMetric
    @State private var target: String
    @State private var selectedPeriod: Period
    @State private var eventKey: String
    @State private var deadline: Date
    @State private var isSaving = false
    @State private var validationMessage: String?

    private static let deadlineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(mode: GoalEditorMode) {
        self.mode = mode
        let goal = mode.goal
        _title = State(initialValue: goal?.title ?? "")
        _description = State(initialValue: goal?.description ?? "")
        _metric = State(initialValue: goal?.metric ?? .bookingsCount)
        _target = State(initialValue: goal.map { Self.targetString($0.target) } ?? "")
        _selectedPeriod = State(initialValue: Self.period(for: goal))
        _eventKey = State(initialValue: goal?.eventKey ?? "")
        _deadline = State(initialValue: Self.date(from: goal?.deadline) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mål") {
                    TextField("Titel", text: $title)
                        .font(SDSType.agrandir(15))

                    TextField("Beskrivning", text: $description, axis: .vertical)
                        .font(SDSType.agrandir(15))
                        .lineLimit(2...4)
                }

                Section("Mått") {
                    Picker("Typ", selection: $metric) {
                        ForEach(GoalMetric.allCases, id: \.self) { metric in
                            Label(metric.title, systemImage: metric.icon)
                                .tag(metric)
                        }
                    }

                    TextField("Målvärde", text: $target)
                        .font(SDSType.agrandir(15))
                        .keyboardType(.decimalPad)
                }

                Section {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(Periods.available) { period in
                            Text(period.displayName).tag(period)
                        }
                    }

                    TextField("Kursnyckel eller kurs-ID", text: $eventKey)
                        .font(SDSType.agrandir(15))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Avgränsning")
                } footer: {
                    Text("Lämna kursnyckel tom för att målet ska gälla vald period. Fyll i kursnyckel eller kurs-ID för ett kursspecifikt mål.")
                }

                Section("Deadline") {
                    DatePicker("Datum", selection: $deadline, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(SDSType.agrandir(13, weight: .bold))
                            .foregroundColor(.sdsPink)
                    }
                }
            }
            .font(SDSType.agrandir(15))
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Spara")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var parsedTarget: Double? {
        let normalized = target
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func save() async {
        validationMessage = nil

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            validationMessage = "Titel saknas."
            return
        }

        guard let parsedTarget, parsedTarget > 0 else {
            validationMessage = "Målvärdet måste vara större än 0."
            return
        }

        isSaving = true
        defer { isSaving = false }

        let cleanEventKey = eventKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = CreateGoalInput(
            title: cleanTitle,
            description: cleanDescription.isEmpty ? nil : cleanDescription,
            metric: metric,
            target: parsedTarget,
            eventBlockId: cleanEventKey.isEmpty ? selectedPeriod.eventBlockId : nil,
            eventKey: cleanEventKey.isEmpty ? nil : cleanEventKey,
            deadline: Self.deadlineFormatter.string(from: deadline)
        )

        let saved: Goal?
        if let goal = mode.goal {
            saved = await goals.updateGoal(id: goal.id, input: input)
        } else {
            saved = await goals.createGoal(input)
        }

        if saved != nil {
            dismiss()
        } else {
            validationMessage = goals.errorMessage ?? "Kunde inte spara målet."
        }
    }

    private static func period(for goal: Goal?) -> Period {
        guard let goal else { return Periods.defaultPeriod() }
        if let eventBlockId = goal.eventBlockId, !eventBlockId.isEmpty {
            return Periods.available.first { $0.eventBlockId == eventBlockId } ?? Periods.all
        }
        return Periods.all
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return deadlineFormatter.date(from: value)
    }

    private static func targetString(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value).replacingOccurrences(of: ".", with: ",")
    }
}

private struct GoalProgressCard: View {
    let goal: Goal
    let currentValue: Double

    private var progress: Double {
        guard goal.target > 0 else { return 0 }
        return min(currentValue / goal.target, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: goal.metric.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Spacer(minLength: 0)

                Text(deadlineText)
                    .font(SDSType.agrandir(12, weight: .bold))
                    .foregroundColor(.white.opacity(0.82))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
                    .lineLimit(1)
            }

            Text(goal.title)
                .font(SDSType.agrandir(24, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let description = goal.description, !description.isEmpty {
                Text(description)
                    .font(SDSType.agrandir(13))
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.2))

                        Capsule()
                            .fill(Color.white)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 9)

                HStack(alignment: .firstTextBaseline) {
                    Text(goal.metric.formatted(currentValue))
                        .font(SDSType.agrandir(18, weight: .bold))
                        .foregroundColor(.white)
                    Spacer(minLength: 6)
                    Text("av \(goal.metric.formatted(goal.target))")
                        .font(SDSType.agrandir(13, weight: .bold))
                        .foregroundColor(.white.opacity(0.78))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 202, alignment: .topLeading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "45aba5"),
                    Color(hex: "2f8f8a")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color(hex: "45aba5").opacity(0.24), radius: 16, x: 0, y: 10)
    }

    private var deadlineText: String {
        let parts = goal.deadline.split(separator: "-")
        guard parts.count == 3 else { return goal.deadline }
        return "\(parts[2])/\(parts[1])"
    }
}

private struct EmptyOverviewSectionCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.sdsDarkModeGreen)
                .frame(width: 38, height: 38)
                .background(Color.sdsIconBackground)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SDSType.agrandir(15, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
                Text(message)
                    .font(SDSType.agrandir(13))
                    .foregroundColor(.sdsSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct CourseOverviewRow: View {
    let row: CourseOverviewData
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.name)
                            .font(SDSType.agrandir(15, weight: .bold))
                            .foregroundColor(.sdsPrimaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if !row.meta.isEmpty {
                            Text(row.meta)
                                .font(SDSType.agrandir(12))
                                .foregroundColor(.sdsSecondaryText)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    SDSBadge(text: row.status.title, color: row.status.background, textColor: row.status.foreground)
                }

                LazyVGrid(columns: metricColumns, spacing: 8) {
                    CourseMiniMetric(title: "Antagna/platser", value: row.acceptedCapacityText)
                    CourseMiniMetric(title: "Beläggning", value: "\(row.occupancyPercent)%")
                    CourseMiniMetric(title: "Intäkt", value: row.revenueText)
                    CourseMiniMetric(title: "Obetalda", value: "\(row.unpaid)", tint: row.unpaid > 0 ? .sdsPink : .sdsDarkModeGreen)
                }
            }
            .padding(16)
            .background(Color.sdsElevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.sdsBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var metricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
    }
}

private struct CourseParticipantRow: View {
    let participant: CourseParticipantData

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(SDSType.agrandir(13, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(participant.booking.status?.name ?? "Accepterad")
                    .font(SDSType.agrandir(11))
                    .foregroundColor(.sdsSecondaryText)
                    .lineLimit(1)
            }

            if participant.isTicketPurchase || participant.isNewStudent || participant.courseChange != nil {
                HStack(spacing: 6) {
                    if participant.isTicketPurchase {
                        SDSBadge(text: "Biljettköp", color: .sdsAmberAdaptiveSurface, textColor: .sdsWarningText)
                    } else if participant.isNewStudent {
                        SDSBadge(text: "Ny elev", color: .sdsLightGreenSurface, textColor: .sdsDarkModeGreen)
                    }

                    if !participant.isTicketPurchase, let courseChange = participant.courseChange {
                        SDSBadge(text: courseChange.badgeText, color: .sdsAmberAdaptiveSurface, textColor: .sdsWarningText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityLabel(courseChange.badgeText)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var name: String {
        participant.booking.participant?.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? participant.booking.participant?.name ?? "Okänd deltagare"
            : "Okänd deltagare"
    }
}

private struct CourseMiniMetric: View {
    let title: String
    let value: String
    var tint: Color = .sdsPrimaryText

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SDSType.agrandir(10, weight: .bold))
                .foregroundColor(.sdsSecondaryText)
                .lineLimit(1)
            Text(value)
                .font(SDSType.agrandir(14, weight: .bold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.sdsSubtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct CourseDetailLine: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(SDSType.agrandir(13))
                    .foregroundColor(.sdsSecondaryText)
                Spacer()
                Text(value)
                    .font(SDSType.agrandir(14, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
            }
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.sdsBorder)
                .frame(height: 1)
        }
    }
}

private struct CourseDetailSheet: View {
    let course: CourseOverviewData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        SDSBadge(
                            text: course.status.title,
                            color: course.status.background,
                            textColor: course.status.foreground
                        )

                        Text(course.name)
                            .font(SDSType.agrandir(20, weight: .bold))
                            .foregroundColor(.sdsPrimaryText)

                        if !course.meta.isEmpty {
                            Text(course.meta)
                                .font(SDSType.agrandir(13))
                                .foregroundColor(.sdsSecondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    VStack(spacing: 0) {
                        CourseDetailLine(label: "Anmälda", value: "\(course.registered)")
                        CourseDetailLine(label: "Antagna", value: "\(course.accepted)")
                        CourseDetailLine(label: "Betalda", value: "\(course.paid)")
                        CourseDetailLine(label: "Obetalda", value: "\(course.unpaid)")
                        CourseDetailLine(label: "Intäkt", value: course.fullRevenueText)
                    }
                    .padding(.horizontal, 20)

                    if !course.participants.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Deltagare")
                                .font(SDSType.agrandir(11, weight: .bold))
                                .foregroundColor(.sdsSecondaryText)
                                .textCase(.uppercase)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 4)

                            VStack(spacing: 0) {
                                ForEach(course.participants) { participant in
                                    CourseParticipantRow(participant: participant)

                                    if participant.id != course.participants.last?.id {
                                        Rectangle()
                                            .fill(Color.sdsBorder)
                                            .frame(height: 1)
                                            .padding(.leading, 20)
                                    }
                                }
                            }
                            .background(Color.sdsElevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.sdsBorder, lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Color.sdsBackground)
            .navigationTitle("Kursdetaljer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Stäng") { dismiss() }
                        .font(SDSType.agrandir(15, weight: .bold))
                }
            }
        }
    }
}

private enum CourseOverviewSort: String, CaseIterable, Identifiable {
    case attention
    case registered
    case occupancy
    case revenue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention: "Åtgärd"
        case .registered: "Anmälda"
        case .occupancy: "Beläggning"
        case .revenue: "Intäkt"
        }
    }
}

private struct CourseOverviewData: Identifiable {
    let id: String
    let name: String
    let meta: String
    let registered: Int
    let accepted: Int
    let capacity: Int?
    let occupancyPercent: Int
    let revenue: Double
    let unpaid: Int
    let paid: Int
    let participants: [CourseParticipantData]
    let status: CourseOverviewStatus

    var revenueText: String {
        revenue > 0 ? "\(Int(revenue / 1000)) tkr" : "—"
    }

    var acceptedCapacityText: String {
        guard let capacity, capacity > 0 else { return "\(accepted)/—" }
        return "\(accepted)/\(capacity)"
    }

    var fullRevenueText: String {
        "\(Int(revenue).formatted(.number.locale(Locale(identifier: "sv_SE")))) kr"
    }
}

private struct CourseParticipantData: Identifiable {
    let booking: Booking
    let isNewStudent: Bool
    let courseChange: ParticipantCourseChange?
    let isTicketPurchase: Bool

    var id: Int { booking.id }
}

private enum CourseOverviewStatus {
    case attention
    case strong
    case low
    case neutral

    var title: String {
        switch self {
        case .attention: "Följ upp"
        case .strong: "Stark"
        case .low: "Låg"
        case .neutral: "OK"
        }
    }

    var background: Color {
        switch self {
        case .attention: .sdsPinkAdaptiveSurface
        case .strong: .sdsLightGreenSurface
        case .low: .sdsAmberAdaptiveSurface
        case .neutral: .sdsSubtleSurface
        }
    }

    var foreground: Color {
        switch self {
        case .attention: .sdsPink
        case .strong: .sdsDarkModeGreen
        case .low: .sdsWarningText
        case .neutral: .sdsSecondaryText
        }
    }
}

private extension GoalMetric {
    var title: String {
        switch self {
        case .bookingsCount: "Anmälningar"
        case .acceptedCount: "Antagna"
        case .revenue: "Intäkt"
        case .occupancy: "Beläggning"
        case .newStudents: "Nya elever"
        }
    }

    var icon: String {
        switch self {
        case .bookingsCount: "person.2"
        case .acceptedCount: "person.crop.circle.badge.checkmark"
        case .revenue: "banknote"
        case .occupancy: "chart.line.uptrend.xyaxis"
        case .newStudents: "sparkles"
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .revenue:
            return "\(Int(value / 1000)) tkr"
        case .occupancy:
            return "\(Int(value.rounded()))%"
        default:
            return Int(value.rounded()).formatted(.number.locale(Locale(identifier: "sv_SE")))
        }
    }
}

private extension Booking {
    nonisolated var overviewPeriodLabel: String? {
        let value = event?.startDateTime ?? created
        let year = String(value.prefix(4))
        guard year.count == 4 else { return nil }

        let monthValue = value.dropFirst(5).prefix(2)
        let month = Int(monthValue) ?? 8
        return month >= 7 ? "Höstterminen \(year)" : "Vårterminen \(year)"
    }
}

#Preview {
    OversiktView()
        .environmentObject(SupabaseAuthService())
        .environmentObject(CogWorkService())
        .environmentObject(GoalsService())
}
