import SwiftUI

struct AnmalningarView: View {
    @EnvironmentObject var cogWork: CogWorkService
    @State private var searchText = ""
    @State private var paymentFilter = PaymentFilter.all
    @State private var selectedBooking: Booking?

    private var periods: [Period] { Periods.available }

    private var filteredBookings: [Booking] {
        periodBookings.filter { booking in
            let matchesSearch = searchText.isEmpty
                || (booking.participant?.name?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (booking.event?.name?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesPayment = paymentFilter.matches(booking)
            return matchesSearch && matchesPayment
        }
        .sorted { $0.created > $1.created }
    }

    private var periodBookings: [Booking] {
        cogWork.periodBookings
    }

    private var statisticalPeriodBookings: [Booking] {
        cogWork.statisticalPeriodBookings
    }

    private var paidCount: Int { statisticalPeriodBookings.filter(\.isPaid).count }
    private var unpaidCount: Int { statisticalPeriodBookings.filter(\.isUnpaid).count }
    private var partialCount: Int { statisticalPeriodBookings.filter(\.isPartiallyPaid).count }
    private var overdueCount: Int { statisticalPeriodBookings.filter { $0.daysOverdue > 0 }.count }

    private var eventLookup: [String: Event] { cogWork.eventLookup }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SDSPeriodPicker(periods: periods, selectedPeriod: $cogWork.selectedPeriod)

                    filterScroller(PaymentFilter.allCases) { filter in
                        SDSPill(title: filter.title(paid: paidCount, unpaid: unpaidCount, overdue: overdueCount, partial: partialCount), isSelected: paymentFilter == filter) {
                            paymentFilter = filter
                        }
                    }

                    searchField
                    listCard
                }
                .padding(20)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                await cogWork.loadAllData()
            }
            .navigationTitle("Anmälningar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    refreshMenu
                }
            }
        }
        .background(Color.sdsPageBackground.ignoresSafeArea())
        .task {
            if cogWork.bookings.isEmpty || cogWork.events.isEmpty {
                await cogWork.loadAllData()
            }
        }
        .sheet(item: $selectedBooking) { booking in
            BookingDetailSheet(booking: booking, relatedBookings: relatedBookings(for: booking))
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.sdsDarkModeGreen)
            TextField("Sök deltagare eller kurs...", text: $searchText)
                .font(SDSType.agrandir(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.sdsSubtleSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var refreshMenu: some View {
        Group {
            if cogWork.isLoading {
                ProgressView()
                    .tint(.sdsDarkModeGreen)
            } else {
                Menu {
                    Button {
                        Task { await cogWork.loadAllData() }
                    } label: {
                        Label("Hämta senaste från proxy", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive) {
                        Task { await cogWork.forceRefreshFromCogWork() }
                    } label: {
                        Label("Rensa proxy och hämta från CogWork", systemImage: "trash.circle")
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.sdsDarkModeGreen)
                .accessibilityLabel("Uppdatera data")
            }
        }
    }

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summaryTitle)
                .font(SDSType.agrandir(14, weight: .bold))
                .foregroundColor(.sdsPrimaryText)

            if let updated = cogWork.lastUpdated {
                Text("Uppdaterad \(updated, format: .dateTime.hour().minute())")
                    .font(SDSType.agrandir(11))
                    .foregroundColor(.sdsTertiaryText)
            }
        }
    }

    // filteredBookings är redan sorterad nyast-först, så lika dagar hamnar i sammanhängande block —
    // det räcker att gruppera grannvis istället för Dictionary(grouping:), som inte bevarar ordningen.
    private var groupedBookings: [(key: String, bookings: [Booking])] {
        var groups: [(key: String, bookings: [Booking])] = []
        for booking in filteredBookings {
            let key = booking.formattedCreatedDate
            if groups.indices.last.map({ groups[$0].key }) == key {
                groups[groups.count - 1].bookings.append(booking)
            } else {
                groups.append((key: key, bookings: [booking]))
            }
        }
        return groups
    }

    private var summaryTitle: String {
        if filteredBookings.count < periodBookings.count {
            return "\(filteredBookings.count) av \(periodBookings.count) anmälningar"
        }

        return "\(periodBookings.count) anmälningar"
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                summaryRow
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.sdsElevatedSurface)

            Rectangle()
                .fill(Color.sdsBorder)
                .frame(height: 1)

            content
        }
        .background(Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var content: some View {
        if cogWork.isLoading && cogWork.bookings.isEmpty {
            ProgressView("Laddar anmälningar...")
                .font(SDSType.agrandir(15, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 220)
        } else if filteredBookings.isEmpty {
            Text("Inga anmälningar hittades")
                .font(SDSType.agrandir(15, weight: .bold))
                .foregroundColor(.sdsMutedText)
                .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedBookings, id: \.key) { group in
                    Section {
                        ForEach(group.bookings) { booking in
                            BookingRow(
                                booking: booking,
                                isNewStudent: isNewStudent(booking),
                                isTicketPurchase: isTicketPurchase(booking),
                                scheduleText: scheduleText(for: booking),
                                showsDate: false
                            )
                                .contentShape(Rectangle())
                                .onTapGesture { selectedBooking = booking }

                            if booking.id != group.bookings.last?.id {
                                Rectangle()
                                    .fill(Color.sdsLightGreen)
                                    .opacity(0.55)
                                    .frame(height: 1)
                                    .padding(.leading, 16)
                            }
                        }
                    } header: {
                        dateSectionHeader(group.key)
                    }
                }
            }
        }
    }

    private func dateSectionHeader(_ text: String) -> some View {
        Text(text)
            .font(SDSType.agrandir(12, weight: .bold))
            .foregroundColor(.sdsSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.sdsElevatedSurface)
    }

    private func filterScroller<Data: RandomAccessCollection, Content: View>(
        _ data: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View where Data.Element: Hashable {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(data), id: \.self) { item in
                    content(item)
                }
            }
        }
    }

    private func isNewStudent(_ booking: Booking) -> Bool {
        CourseMetricsEngine.isNewStudentBooking(booking, countByParticipant: cogWork.bookingCountByParticipant)
    }

    private func isTicketPurchase(_ booking: Booking) -> Bool {
        CourseMetricsEngine.isPerformance(booking: booking, eventLookup: eventLookup)
    }

    private func scheduleText(for booking: Booking) -> String? {
        booking.courseScheduleText(eventLookup: eventLookup)
    }

    private func relatedBookings(for booking: Booking) -> [Booking] {
        let identifier = booking.participant?.key ?? booking.participant?.name
        return cogWork.bookings.filter { ($0.participant?.key ?? $0.participant?.name) == identifier }
    }

}

private enum PaymentFilter: CaseIterable, Hashable {
    case all
    case paid
    case unpaid
    case overdue
    case partial

    func title(paid: Int, unpaid: Int, overdue: Int, partial: Int) -> String {
        switch self {
        case .all: "Alla"
        case .paid: "Betalda (\(paid))"
        case .unpaid: "Obetalda (\(unpaid))"
        case .overdue: "Förfallna (\(overdue))"
        case .partial: "Delbetalda (\(partial))"
        }
    }

    func matches(_ booking: Booking) -> Bool {
        switch self {
        case .all: true
        case .paid: booking.isPaid
        case .unpaid: booking.isUnpaid
        case .overdue: booking.daysOverdue > 0
        case .partial: booking.isPartiallyPaid
        }
    }
}

struct BookingRow: View {
    let booking: Booking
    let isNewStudent: Bool
    let isTicketPurchase: Bool
    let scheduleText: String?
    var showsDate: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if showsDate {
                Text(booking.formattedCreatedDate)
                    .font(SDSType.agrandir(12))
                    .foregroundColor(.sdsMutedText)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(booking.participant?.name ?? "Okänd deltagare")
                            .font(SDSType.agrandir(16, weight: .bold))
                            .foregroundColor(.sdsPrimaryText)
                            .lineLimit(2)

                        if isTicketPurchase {
                            SDSBadge(text: "Biljettköp", color: .sdsAmberAdaptiveSurface, textColor: .sdsWarningText)
                        } else if isNewStudent {
                            SDSBadge(text: "Ny elev", color: .sdsLightGreenSurface, textColor: .sdsDarkModeGreen)
                        }
                    }

                    Text(booking.event?.name ?? "Okänd kurs")
                        .font(SDSType.agrandir(14))
                        .foregroundColor(.sdsSecondaryText)
                        .lineLimit(2)

                    if let scheduleText {
                        Label(scheduleText, systemImage: "calendar")
                            .font(SDSType.agrandir(12, weight: .bold))
                            .foregroundColor(.sdsSecondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 10)

                Text(booking.formattedPrice)
                    .font(SDSType.agrandir(15, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
                    .multilineTextAlignment(.trailing)
            }

            SDSBadge(
                // Priset står redan uppe till höger – upprepa det inte i badgen för betalda.
                text: booking.isPaid ? "Betald" : booking.paymentBadgeText,
                color: booking.paymentBadgeColor,
                textColor: booking.paymentTextColor
            )

            // "Accepterad" är normalläget – visa status bara när den avviker.
            if let statusName = booking.status?.displayName, statusName != "Accepterad" {
                Text(statusName)
                    .font(SDSType.agrandir(12))
                    .foregroundColor(.sdsSecondaryText)
            }
        }
        .padding(16)
        .background(Color.sdsElevatedSurface)
    }
}

struct BookingDetailSheet: View {
    let booking: Booking
    let relatedBookings: [Booking]
    @EnvironmentObject var cogWork: CogWorkService
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @State private var customer: CogWorkUser?
    @State private var isLoadingCustomer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DELTAGARE")
                            .font(SDSType.agrandir(12, weight: .bold))
                            .foregroundColor(.sdsMidGreen)
                        Text(customerName)
                            .font(SDSType.agrandir(30, weight: .bold))
                            .foregroundColor(.sdsPrimaryText)
                    }

                    VStack(spacing: 18) {
                        if isLoadingCustomer {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(.sdsDarkModeGreen)
                                Text("Hämtar kunduppgifter...")
                                    .font(SDSType.agrandir(13, weight: .bold))
                                    .foregroundColor(.sdsSecondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        DetailInfoRow(icon: "calendar", label: "Födelsedag", value: dateOfBirthText)
                        DetailInfoRow(icon: "envelope", label: "E-post", value: emailText)
                        DetailInfoRow(icon: "phone", label: "Telefon", value: phoneText)
                        DetailInfoRow(icon: "mappin.and.ellipse", label: "Adress", value: addressText)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "book.closed")
                                .foregroundColor(.sdsDarkGreen)
                            Text("KURSER")
                                .font(SDSType.agrandir(12, weight: .bold))
                                .foregroundColor(.sdsMidGreen)
                        }

                        VStack(spacing: 0) {
                            ForEach(relatedBookings.isEmpty ? [booking] : relatedBookings) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.event?.name ?? "Okänd kurs")
                                        .font(SDSType.agrandir(16, weight: .bold))
                                        .foregroundColor(.sdsPrimaryText)
                                    Text(item.status?.name ?? "Accepterad")
                                        .font(SDSType.agrandir(14))
                                        .foregroundColor(.sdsMutedText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 13)

                                if item.id != (relatedBookings.isEmpty ? booking.id : relatedBookings.last?.id) {
                                    Rectangle()
                                        .fill(Color.sdsLightGreen)
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Color.sdsSurface.ignoresSafeArea())
            .task(id: booking.id) {
                await loadCustomer()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stäng") { dismiss() }
                        .font(SDSType.agrandir(15, weight: .bold))
                        .foregroundColor(.sdsDarkGreen)
                }
            }
        }
    }

    private var customerName: String {
        customer?.name?.nilIfEmpty
            ?? [customer?.firstName, customer?.lastName]
                .compactMap { $0?.nilIfEmpty }
                .joined(separator: " ")
                .nilIfEmpty
            ?? booking.participant?.name?.nilIfEmpty
            ?? "Okänd deltagare"
    }

    private var dateOfBirthText: String {
        customer?.dateOfBirth?.nilIfEmpty
            ?? booking.participant?.dateOfBirth?.nilIfEmpty
            ?? "Saknas i bokningsdatan"
    }

    private var emailText: String {
        customer?.emails?.compactMap { $0.email?.nilIfEmpty }.first
            ?? "Saknas i kunddatan"
    }

    private var phoneText: String {
        customer?.telephoneNumbers?.compactMap { $0.telephoneNumber?.nilIfEmpty }.first
            ?? booking.participant?.telephoneNumbers?.compactMap { $0.telephoneNumber?.nilIfEmpty }.first
            ?? "Saknas i kunddatan"
    }

    private var addressText: String {
        customer?.addresses?.map(\.bookingDetailDisplayText).first { !$0.isEmpty }
            ?? "Saknas i kunddatan"
    }

    private func loadCustomer() async {
        guard !cogWork.cogWorkPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let name = booking.participant?.name?.nilIfEmpty else {
            return
        }

        isLoadingCustomer = true
        defer { isLoadingCustomer = false }
        customer = await cogWork.loadUser(named: name)
    }
}

private struct DetailInfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.sdsDarkGreen)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(SDSType.agrandir(11, weight: .bold))
                    .foregroundColor(.sdsMidGreen)
                Text(value)
                    .font(SDSType.agrandir(15))
                    .foregroundColor(.sdsPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

extension Booking {
    var isPaid: Bool {
        payment?.paid == true
    }

    var isPartiallyPaid: Bool {
        payment?.paid != true && (payment?.amountPaid ?? 0) > 0
    }

    var isUnpaid: Bool {
        payment?.paid == false && !isPartiallyPaid
    }

    var paymentBadgeText: String {
        if isPaid {
            let amount = payment?.amountPaid ?? payment?.priceAgreed ?? 0
            return "Betald · \(Int(amount)) kr"
        }

        if isPartiallyPaid {
            return "Delbetald · \(Int(payment?.amountPaid ?? 0)) kr"
        }

        let overdue = daysOverdue
        if overdue > 0 {
            return "Förfallen · \(overdue) \(overdue == 1 ? "dag" : "dagar")"
        }

        if let due = payment?.paymentDue, !due.isEmpty {
            return "Obetald · förfaller \(due)"
        }

        return "Obetald"
    }

    var paymentBadgeColor: Color {
        if isPaid { return .sdsLightGreen }
        if isPartiallyPaid { return .sdsAmberSurface }
        if daysOverdue > 0 { return Self.overdueBadgeColor }
        return .sdsPinkSurface
    }

    var paymentTextColor: Color {
        if isPaid { return .sdsDarkGreen }
        if isPartiallyPaid { return .sdsWarningText }
        if daysOverdue > 0 { return .white }
        return .sdsPink
    }

    /// Mörk rosa (#B4234F) – vit text på den ger ≈ 6,4:1 kontrast.
    private static let overdueBadgeColor = Color(red: 180 / 255, green: 35 / 255, blue: 79 / 255)

    /// Antal hela dagar sedan förfallodagen passerat (0 = ej förfallen / ej obetald).
    /// Datum utan klockslag gäller hela förfallodagen. Samma regel som webbens daysOverdue.
    nonisolated var daysOverdue: Int {
        guard payment?.paid == false,
              !((payment?.amountPaid ?? 0) > 0),
              let rawDue = payment?.paymentDue?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawDue.count >= 10 else { return 0 }

        let dateParts = rawDue.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard dateParts.count == 3 else { return 0 }

        var components = DateComponents(year: dateParts[0], month: dateParts[1], day: dateParts[2], hour: 23, minute: 59, second: 59)
        let hasExplicitTime = rawDue.count >= 16
        if hasExplicitTime {
            let timeParts = rawDue.dropFirst(11).prefix(8).split(separator: ":").compactMap { Int($0) }
            if timeParts.count >= 2 {
                components.hour = timeParts[0]
                components.minute = timeParts[1]
                components.second = timeParts.count > 2 ? timeParts[2] : 0
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        guard let dueDate = calendar.date(from: components), dueDate < Date() else { return 0 }

        if hasExplicitTime {
            // Exakt tid angiven — räkna faktisk förfluten tid
            let elapsed = Date().timeIntervalSince(dueDate)
            return max(1, Int(elapsed / 86_400))
        }

        // Bara datum angivet — hela förfallodagen gäller, så det är antal hela kalenderdagar
        // sedan förfallodagen, inte avrundad förfluten tid (som skulle ge "7 dagar sedan" -> 6).
        let dueDay = calendar.startOfDay(for: dueDate)
        let today = calendar.startOfDay(for: Date())
        return max(0, calendar.dateComponents([.day], from: dueDay, to: today).day ?? 0)
    }

    var formattedCreatedDate: String {
        let normalized = created.replacingOccurrences(of: " ", with: "T")
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: normalized) ?? Self.fallbackDateFormatter.date(from: created) else {
            return created
        }

        let output = DateFormatter()
        output.locale = Locale(identifier: "sv_SE")
        output.dateFormat = "d MMM yyyy"
        return output.string(from: date)
    }

    private static let fallbackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var periodLabel: String? {
        let value = event?.startDateTime ?? created
        let year = String(value.prefix(4))
        guard year.count == 4 else { return nil }

        let monthValue = value.dropFirst(5).prefix(2)
        let month = Int(monthValue) ?? 8
        return month >= 7 ? "Höstterminen \(year)" : "Vårterminen \(year)"
    }

    func courseScheduleText(eventLookup: [String: Event]) -> String? {
        let fullEvent = [event?.id.map(String.init), event?.key]
            .compactMap { $0 }
            .compactMap { eventLookup[$0] }
            .first

        if let dayAndTimeInfo = fullEvent?.schedule?.dayAndTimeInfo?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !dayAndTimeInfo.isEmpty {
            return dayAndTimeInfo
        }

        if let startDateTime = event?.startDateTime,
           let formatted = Self.formattedSwedishDayAndTime(from: startDateTime) {
            return formatted
        }

        let combinedStart = [event?.startDate, event?.startTime]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !combinedStart.isEmpty else { return nil }
        if let formatted = Self.formattedSwedishDayAndTime(from: combinedStart) {
            return formatted
        }

        return combinedStart
    }

    private static func formattedSwedishDayAndTime(from value: String) -> String? {
        let normalized = value.replacingOccurrences(of: " ", with: "T")
        let date = isoDateTimeFormatter.date(from: normalized)
            ?? isoDateTimeWithFractionalSecondsFormatter.date(from: normalized)
            ?? fallbackDateTimeFormatter.date(from: value)
            ?? fallbackShortDateTimeFormatter.date(from: value)
            ?? fallbackDateOnlyFormatter.date(from: value)
        guard let date else { return nil }

        let weekday = swedishWeekdayFormatter.string(from: date)
        let time = timeFormatter.string(from: date)
        return "\(weekday) \(time)"
    }

    private static let isoDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoDateTimeWithFractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let fallbackShortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let fallbackDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let swedishWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private extension UserAddress {
    var bookingDetailDisplayText: String {
        [
            careOf,
            streetAddress,
            [postalCode, city].compactMap { $0?.nilIfEmpty }.joined(separator: " "),
            country == "SE" ? nil : country
        ]
        .compactMap { $0?.nilIfEmpty }
        .joined(separator: "\n")
    }
}

private extension Booking.BookingStatus {
    var displayName: String {
        BookingStatusFormatter.format(code: code, fallback: name)
    }
}

#Preview {
    AnmalningarView()
        .environmentObject(CogWorkService())
}
