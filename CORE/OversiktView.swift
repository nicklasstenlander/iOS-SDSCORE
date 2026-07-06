import SwiftUI

struct OversiktView: View {
    @EnvironmentObject var auth: SupabaseAuthService
    @EnvironmentObject var cogWork: CogWorkService
    @EnvironmentObject var goals: GoalsService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var expandedCard: OverviewCardID?
    @State private var expandedCourseID: String?
    @State private var courseSort = CourseOverviewSort.attention
    @State private var courseSearchText = ""

    private var periods: [Period] { Periods.available }

    private var periodBookings: [Booking] {
        cogWork.periodBookings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                filters
                overviewKPIs
                goalsSection
                courseOverviewSection

                if let error = cogWork.errorMessage {
                    Text(error)
                        .font(SDSType.rounded(13, weight: .bold))
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
        }
        .background(Color.sdsPageBackground.ignoresSafeArea())
        .refreshable {
            await cogWork.forceRefreshFromCogWork()
        }
        .task {
            if cogWork.bookings.isEmpty {
                await cogWork.loadBookings()
            }
            if goals.goals.isEmpty {
                await goals.loadGoals()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(todayLabel)\(periodCode.isEmpty ? "" : " · \(periodCode)")")
                .font(SDSType.rounded(12, weight: .bold))
                .foregroundColor(.sdsDarkModeGreen)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(greeting),")
                    .font(SDSType.rounded(42, weight: .light))
                    .italic()
                    .foregroundColor(.sdsPrimaryText)
                Text("\(greetingName).")
                    .font(SDSType.rounded(42, weight: .regular))
                    .foregroundColor(.sdsPrimaryText)
            }

            if cogWork.isLoading {
                ProgressView("Laddar...")
                    .font(SDSType.rounded(15, weight: .bold))
                    .tint(.sdsDarkGreen)
            } else if !statLine.isEmpty {
                Text(statLine)
                    .font(SDSType.rounded(14))
                    .foregroundColor(.sdsSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Period")
                .font(SDSType.rounded(12, weight: .bold))
                .foregroundColor(.sdsSecondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(periods, id: \.self) { period in
                        SDSPill(title: period.displayName, isSelected: cogWork.selectedPeriod == period) {
                            cogWork.selectedPeriod = period
                        }
                    }
                }
            }
        }
    }

    private var overviewKPIs: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Översikt")
                .font(SDSType.rounded(22, weight: .bold))
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
                    .font(SDSType.rounded(22, weight: .bold))
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
                    .font(SDSType.rounded(13, weight: .bold))
                    .foregroundColor(.sdsPink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.sdsPinkAdaptiveSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if activeGoals.isEmpty {
                EmptyOverviewSectionCard(
                    icon: "target",
                    title: "Inga aktiva mål",
                    message: "När mål finns i dashboarden visas de här med progress och deadline."
                )
            } else {
                LazyVGrid(columns: goalColumns, spacing: 12) {
                    ForEach(activeGoals.prefix(4)) { goal in
                        GoalProgressCard(goal: goal, currentValue: currentValue(for: goal))
                    }
                }
            }
        }
    }

    private var courseOverviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kursöversikt")
                        .font(SDSType.rounded(22, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)

                    if let updated = cogWork.lastUpdated {
                        Text("Uppdaterad \(updated, format: .dateTime.hour().minute())")
                            .font(SDSType.rounded(11))
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
                        .font(SDSType.rounded(12, weight: .bold))
                        .foregroundColor(.sdsDarkModeGreen)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Color.sdsSurface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.sdsBorder, lineWidth: 1))
                }
            }

            courseSearchField

            if courseRows.isEmpty {
                EmptyOverviewSectionCard(
                    icon: "book.closed",
                    title: "Ingen kursdata",
                    message: "Kursöversikten fylls när det finns anmälningar i vald period."
                )
            } else if filteredCourseRows.isEmpty {
                EmptyOverviewSectionCard(
                    icon: "magnifyingglass",
                    title: "Inga kurser matchar",
                    message: "Ändra sökningen eller rensa fältet för att visa alla kurser igen."
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(sortedCourseRows) { row in
                        CourseOverviewRow(
                            row: row,
                            isExpanded: expandedCourseID == row.id
                        ) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                expandedCourseID = expandedCourseID == row.id ? nil : row.id
                            }
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
                .font(SDSType.rounded(14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !courseSearchText.isEmpty {
                Button {
                    courseSearchText = ""
                    expandedCourseID = nil
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
        return periodBookings.filter { $0.created.hasPrefix(today) }.count
    }

    private var unpaidCount: Int {
        periodBookings.filter { $0.payment?.paid == false }.count
    }

    private var acceptedCount: Int {
        periodBookings.filter { $0.isAcceptedForOverview }.count
    }

    private var awaitingCount: Int {
        periodBookings.filter { $0.isAwaitingResponseForOverview }.count
    }

    private var acceptedPercent: Int {
        guard !periodBookings.isEmpty else { return 0 }
        return Int((Double(acceptedCount) / Double(periodBookings.count) * 100).rounded())
    }

    private var uniqueCourseCount: Int {
        Set(periodBookings.compactMap { $0.event?.id.map(String.init) ?? $0.event?.name }).count
    }

    private var paidCount: Int {
        periodBookings.filter { $0.payment?.paid == true }.count
    }

    private var unpaidAmount: Double {
        periodBookings
            .filter { $0.payment?.paid == false }
            .compactMap { $0.payment?.priceAgreed }
            .reduce(0, +)
    }

    private var receivedPercent: Int {
        guard totalInvoiced > 0 else { return 0 }
        return Int((totalReceived / totalInvoiced * 100).rounded())
    }

    private var totalInvoiced: Double {
        periodBookings
            .filter(\.isAcceptedForOverview)
            .compactMap { $0.payment?.priceAgreed }
            .reduce(0, +)
    }

    private var totalReceived: Double {
        periodBookings
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
                value: formatted(periodBookings.count),
                subtitle: "\(uniqueCourseCount) kurser",
                delta: newTodayCount > 0 ? "+\(newTodayCount) idag" : nil,
                icon: "person.2",
                style: .violet,
                detailTitle: "Anmälningar",
                detailRows: [
                    .init(label: "Totalt antal", value: formatted(periodBookings.count)),
                    .init(label: "Nya idag", value: formatted(newTodayCount)),
                    .init(label: "Unika kurser", value: formatted(uniqueCourseCount))
                ],
                bookings: sortedBookingsForPanel(periodBookings)
            ),
            OverviewCard(
                id: .accepted,
                title: "Antagna",
                value: formatted(acceptedCount),
                subtitle: periodBookings.isEmpty ? "Ingen data" : "\(acceptedPercent)% av anmälda",
                icon: "person.crop.circle.badge.checkmark",
                style: .ok,
                detailTitle: "Antagna deltagare",
                detailRows: [
                    .init(label: "Antagna", value: formatted(acceptedCount)),
                    .init(label: "Andel", value: "\(acceptedPercent)%"),
                    .init(label: "Ej antagna/okänt", value: formatted(max(periodBookings.count - acceptedCount, 0)))
                ],
                bookings: sortedBookingsForPanel(periodBookings.filter(\.isAcceptedForOverview))
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
                bookings: sortedBookingsForPanel(periodBookings.filter { $0.payment?.paid == false })
            ),
            OverviewCard(
                id: .awaiting,
                title: "Återkoppling",
                value: formatted(awaitingCount),
                subtitle: awaitingCount > 0 ? "Manuell check" : "Inga ärenden",
                icon: "clock",
                style: awaitingCount > 0 ? .warning : .ok,
                detailTitle: "Väntar återkoppling",
                detailRows: [
                    .init(label: "Ärenden", value: formatted(awaitingCount)),
                    .init(label: "Period", value: cogWork.selectedPeriod.displayName),
                    .init(label: "Status", value: awaitingCount > 0 ? "Behöver åtgärd" : "Klart")
                ],
                bookings: sortedBookingsForPanel(periodBookings.filter(\.isAwaitingResponseForOverview))
            ),
            OverviewCard(
                id: .courses,
                title: "Kurser",
                value: formatted(uniqueCourseCount),
                subtitle: "aktiva i urvalet",
                icon: "book.closed",
                style: .sky,
                detailTitle: "Kursunderlag",
                detailRows: [
                    .init(label: "Aktiva kurser", value: formatted(uniqueCourseCount)),
                    .init(label: "Anmälningar/kurs", value: averageBookingsPerCourse),
                    .init(label: "Datakälla", value: "CogWork bokningar")
                ]
            ),
            OverviewCard(
                id: .occupancy,
                title: "Beläggning",
                value: "—",
                subtitle: "kräver kursplatser",
                icon: "chart.line.uptrend.xyaxis",
                style: .emerald,
                detailTitle: "Beläggning",
                detailRows: [
                    .init(label: "Nuvarande värde", value: "Saknas"),
                    .init(label: "Behöver", value: "Maxplatser per kurs"),
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
                ],
                bookings: sortedBookingsForPanel(periodBookings.filter { $0.isAcceptedForOverview && $0.payment?.priceAgreed != nil })
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
                ],
                bookings: sortedBookingsForPanel(periodBookings.filter { $0.payment?.paid == true })
            )
        ]
    }

    private func sortedBookingsForPanel(_ bookings: [Booking]) -> [Booking] {
        bookings.sorted { $0.created.localizedStandardCompare($1.created) == .orderedDescending }
    }

    private var averageBookingsPerCourse: String {
        guard uniqueCourseCount > 0 else { return "—" }
        let average = Double(periodBookings.count) / Double(uniqueCourseCount)
        return average.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "sv_SE")))
    }

    private var activeGoals: [Goal] {
        goals.goals
            .filter { $0.archived != 1 }
            .sorted { $0.deadline.localizedStandardCompare($1.deadline) == .orderedAscending }
    }

    private func currentValue(for goal: Goal) -> Double {
        switch goal.metric {
        case .bookingsCount:
            Double(periodBookings.count)
        case .acceptedCount:
            Double(acceptedCount)
        case .revenue:
            totalInvoiced
        case .occupancy:
            0
        case .newStudents:
            Double(newStudentCount)
        }
    }

    private var newStudentCount: Int {
        let counts = CourseMetricsEngine.countBookingsByParticipant(periodBookings)
        return periodBookings.filter { CourseMetricsEngine.isNewStudentBooking($0, countByParticipant: counts) }.count
    }

    private var courseRows: [CourseOverviewData] {
        let grouped = Dictionary(grouping: periodBookings) { booking in
            booking.event?.id.map(String.init) ?? booking.event?.name ?? booking.key
        }

        return grouped.compactMap { key, bookings in
            guard let first = bookings.first else { return nil }
            let accepted = bookings.filter(\.isAcceptedForOverview).count
            let unpaid = bookings.filter { $0.payment?.paid == false }.count
            let revenue = bookings
                .filter(\.isAcceptedForOverview)
                .compactMap { $0.payment?.priceAgreed }
                .reduce(0, +)
            let paid = bookings.filter { $0.payment?.paid == true }.count
            let percent = bookings.isEmpty ? 0 : Int((Double(accepted) / Double(bookings.count) * 100).rounded())

            return CourseOverviewData(
                id: key,
                name: first.event?.name ?? "Okänd kurs",
                meta: courseMeta(for: first),
                registered: bookings.count,
                accepted: accepted,
                occupancyPercent: percent,
                revenue: revenue,
                unpaid: unpaid,
                paid: paid,
                status: courseStatus(accepted: accepted, registered: bookings.count, unpaid: unpaid)
            )
        }
    }

    private var sortedCourseRows: [CourseOverviewData] {
        switch courseSort {
        case .attention:
            return filteredCourseRows.sorted {
                if $0.unpaid == $1.unpaid { return $0.registered > $1.registered }
                return $0.unpaid > $1.unpaid
            }
        case .registered:
            return filteredCourseRows.sorted { $0.registered > $1.registered }
        case .occupancy:
            return filteredCourseRows.sorted { $0.occupancyPercent < $1.occupancyPercent }
        case .revenue:
            return filteredCourseRows.sorted { $0.revenue > $1.revenue }
        }
    }

    private var filteredCourseRows: [CourseOverviewData] {
        let query = courseSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return courseRows }
        return courseRows.filter { row in
            row.name.localizedCaseInsensitiveContains(query)
                || row.meta.localizedCaseInsensitiveContains(query)
                || row.status.title.localizedCaseInsensitiveContains(query)
        }
    }

    private func courseMeta(for booking: Booking) -> String {
        let period = booking.overviewPeriodLabel.map {
            $0.replacingOccurrences(of: "Höstterminen ", with: "HT")
                .replacingOccurrences(of: "Vårterminen ", with: "VT")
        }
        let start = [booking.event?.startDate, booking.event?.startTime]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")

        return [period, start.isEmpty ? nil : start]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func courseStatus(accepted: Int, registered: Int, unpaid: Int) -> CourseOverviewStatus {
        if unpaid > 0 { return .attention }
        guard registered > 0 else { return .neutral }
        let percent = Double(accepted) / Double(registered)
        if percent >= 0.85 { return .strong }
        if percent <= 0.45 { return .low }
        return .neutral
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
    var bookings: [Booking] = []
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(SDSType.rounded(11))
                        .foregroundColor(titleColor)
                        .lineLimit(1)

                    Text(value)
                        .font(SDSType.rounded(20, weight: .bold))
                        .foregroundColor(valueColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let subtitle {
                        Text(subtitle)
                            .font(SDSType.rounded(9))
                            .foregroundColor(valueColor.opacity(0.72))
                            .lineLimit(1)
                    }

                    if let delta {
                        Text(delta)
                            .font(SDSType.rounded(9, weight: .bold))
                            .foregroundColor(deltaColor)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 30, height: 30)
                    .background(iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }

            HStack {
                Text(isExpanded ? "Visar detaljer" : "Tryck för mer")
                    .font(SDSType.rounded(8, weight: .bold))
                    .foregroundColor(valueColor.opacity(0.62))
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(valueColor.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .padding(10)
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
        case .dark: .white.opacity(0.8)
        case .warning: .sdsWarningText
        default: .sdsSecondaryText
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
        style == .dark ? .white.opacity(0.12) : .white.opacity(0.62)
    }
}

private struct ExpandedKPICard: View {
    let card: OverviewCard

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: card.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.sdsDarkModeGreen)
                    .frame(width: 42, height: 42)
                    .background(Color.sdsLightGreenSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.detailTitle)
                        .font(SDSType.rounded(20, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)
                    Text("Detaljer för \(card.title.lowercased()) i vald period.")
                        .font(SDSType.rounded(13))
                        .foregroundColor(.sdsSecondaryText)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(card.detailRows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .font(SDSType.rounded(13))
                            .foregroundColor(.sdsSecondaryText)
                        Spacer(minLength: 12)
                        Text(row.value)
                            .font(SDSType.rounded(15, weight: .bold))
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

            if !card.bookings.isEmpty {
                OverviewBookingList(bookings: card.bookings)
            }
        }
        .padding(18)
        .background(Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct OverviewBookingList: View {
    let bookings: [Booking]

    private var visibleBookings: [Booking] {
        Array(bookings.prefix(12))
    }

    private var ticketCount: Int {
        bookings.reduce(0) { $0 + CourseMetricsEngine.bookingTicketQuantity($1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Poster")
                    .font(SDSType.rounded(13, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)

                Spacer()

                Text(summary)
                    .font(SDSType.rounded(11, weight: .bold))
                    .foregroundColor(.sdsSecondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 8)

            ForEach(visibleBookings) { booking in
                OverviewBookingRow(booking: booking)

                if booking.id != visibleBookings.last?.id {
                    Rectangle()
                        .fill(Color.sdsBorder)
                        .frame(height: 1)
                        .padding(.leading, 56)
                }
            }

            if bookings.count > visibleBookings.count {
                Text("+ \(bookings.count - visibleBookings.count) fler poster")
                    .font(SDSType.rounded(12, weight: .bold))
                    .foregroundColor(.sdsSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .background(Color.sdsSubtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var summary: String {
        if ticketCount == bookings.count {
            return "\(bookings.count) personer"
        }
        return "\(ticketCount) biljetter · \(bookings.count) köp"
    }
}

private struct OverviewBookingRow: View {
    let booking: Booking

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
                        .font(SDSType.rounded(11, weight: .bold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(SDSType.rounded(13, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
                    .lineLimit(1)

                Text(booking.event?.name ?? "Okänd kurs")
                    .font(SDSType.rounded(11))
                    .foregroundColor(.sdsSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if ticketQuantity > 1 {
                SDSBadge(text: "\(ticketQuantity) biljetter", color: .sdsSurface, textColor: .sdsSecondaryText)
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

private struct GoalProgressCard: View {
    let goal: Goal
    let currentValue: Double

    private var progress: Double {
        guard goal.target > 0 else { return 0 }
        return min(currentValue / goal.target, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: goal.metric.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.sdsDarkModeGreen)
                    .frame(width: 36, height: 36)
                    .background(Color.sdsLightGreenSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 11))

                Spacer(minLength: 0)

                Text(deadlineText)
                    .font(SDSType.rounded(10, weight: .bold))
                    .foregroundColor(.sdsSecondaryText)
                    .lineLimit(1)
            }

            Text(goal.title)
                .font(SDSType.rounded(14, weight: .bold))
                .foregroundColor(.sdsPrimaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                ProgressView(value: progress)
                    .tint(.sdsDarkModeGreen)

                HStack(alignment: .firstTextBaseline) {
                    Text(goal.metric.formatted(currentValue))
                        .font(SDSType.rounded(13, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)
                    Spacer(minLength: 6)
                    Text("av \(goal.metric.formatted(goal.target))")
                        .font(SDSType.rounded(11))
                        .foregroundColor(.sdsSecondaryText)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .padding(14)
        .background(Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
                .background(Color.sdsLightGreenSurface)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SDSType.rounded(15, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
                Text(message)
                    .font(SDSType.rounded(13))
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
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.name)
                            .font(SDSType.rounded(15, weight: .bold))
                            .foregroundColor(.sdsPrimaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if !row.meta.isEmpty {
                            Text(row.meta)
                                .font(SDSType.rounded(12))
                                .foregroundColor(.sdsSecondaryText)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    SDSBadge(text: row.status.title, color: row.status.background, textColor: row.status.foreground)
                }

                LazyVGrid(columns: metricColumns, spacing: 8) {
                    CourseMiniMetric(title: "Antagna", value: "\(row.accepted)/\(row.registered)")
                    CourseMiniMetric(title: "Beläggning", value: "\(row.occupancyPercent)%")
                    CourseMiniMetric(title: "Intäkt", value: row.revenueText)
                    CourseMiniMetric(title: "Obetalda", value: "\(row.unpaid)", tint: row.unpaid > 0 ? .sdsPink : .sdsDarkModeGreen)
                }

                if isExpanded {
                    VStack(spacing: 0) {
                        CourseDetailLine(label: "Anmälda", value: "\(row.registered)")
                        CourseDetailLine(label: "Antagna", value: "\(row.accepted)")
                        CourseDetailLine(label: "Betalda", value: "\(row.paid)")
                        CourseDetailLine(label: "Obetalda", value: "\(row.unpaid)")
                        CourseDetailLine(label: "Intäkt", value: row.fullRevenueText)
                    }
                    .padding(.horizontal, 14)
                    .background(Color.sdsSubtleSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack {
                    Text(isExpanded ? "Dölj detaljer" : "Visa detaljer")
                        .font(SDSType.rounded(11, weight: .bold))
                        .foregroundColor(.sdsSecondaryText)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.sdsSecondaryText)
                }
            }
            .padding(16)
            .background(Color.sdsElevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isExpanded ? Color.sdsDarkModeGreen.opacity(0.42) : Color.sdsBorder, lineWidth: isExpanded ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var metricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
    }
}

private struct CourseMiniMetric: View {
    let title: String
    let value: String
    var tint: Color = .sdsPrimaryText

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SDSType.rounded(10, weight: .bold))
                .foregroundColor(.sdsSecondaryText)
                .lineLimit(1)
            Text(value)
                .font(SDSType.rounded(14, weight: .bold))
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
                    .font(SDSType.rounded(13))
                    .foregroundColor(.sdsSecondaryText)
                Spacer()
                Text(value)
                    .font(SDSType.rounded(14, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
            }
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.sdsBorder)
                .frame(height: 1)
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
    let occupancyPercent: Int
    let revenue: Double
    let unpaid: Int
    let paid: Int
    let status: CourseOverviewStatus

    var revenueText: String {
        revenue > 0 ? "\(Int(revenue / 1000)) tkr" : "—"
    }

    var fullRevenueText: String {
        "\(Int(revenue).formatted(.number.locale(Locale(identifier: "sv_SE")))) kr"
    }
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
    var overviewPeriodLabel: String? {
        let value = event?.startDateTime ?? created
        let year = String(value.prefix(4))
        guard year.count == 4 else { return nil }

        let monthValue = value.dropFirst(5).prefix(2)
        let month = Int(monthValue) ?? 8
        return month >= 7 ? "Höstterminen \(year)" : "Vårterminen \(year)"
    }

    var isAcceptedForOverview: Bool {
        let code = status?.code?.uppercased() ?? ""
        let name = status?.name?.lowercased() ?? ""
        return code == "ACCEPTED" || name.contains("accepterad") || name.contains("antagen")
    }

    var isAwaitingResponseForOverview: Bool {
        let code = status?.code?.uppercased() ?? ""
        let name = status?.name?.lowercased() ?? ""
        return code == "AWAITING_RESPONSE" || code == "WAITING" || name.contains("väntar")
    }
}

#Preview {
    OversiktView()
        .environmentObject(SupabaseAuthService())
        .environmentObject(CogWorkService())
        .environmentObject(GoalsService())
}
