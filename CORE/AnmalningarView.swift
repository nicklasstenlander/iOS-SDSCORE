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
        let lookup = eventLookup
        return periodBookings.filter { CourseMetricsEngine.isStatisticalBooking($0, eventLookup: lookup) }
    }

    private var paidCount: Int { statisticalPeriodBookings.filter(\.isPaid).count }
    private var unpaidCount: Int { statisticalPeriodBookings.filter(\.isUnpaid).count }
    private var partialCount: Int { statisticalPeriodBookings.filter(\.isPartiallyPaid).count }

    private var bookingCountByParticipant: [String: Int] {
        CourseMetricsEngine.countBookingsByParticipant(cogWork.bookings, eventLookup: eventLookup)
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SDSPeriodPicker(periods: periods, selectedPeriod: $cogWork.selectedPeriod)

                    filterScroller(PaymentFilter.allCases) { filter in
                        SDSPill(title: filter.title(paid: paidCount, unpaid: unpaidCount, partial: partialCount), isSelected: paymentFilter == filter) {
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

            HStack(spacing: 14) {
                SummaryMetric(value: paidCount, label: "betalda", color: .sdsDarkGreen)
                SummaryMetric(value: unpaidCount, label: "obetalda", color: .sdsPink)
                if partialCount > 0 {
                    SummaryMetric(value: partialCount, label: "delbetalda", color: .sdsWarningText)
                }
            }

            if let updated = cogWork.lastUpdated {
                Text("Uppdaterad \(updated, format: .dateTime.hour().minute())")
                    .font(SDSType.agrandir(11))
                    .foregroundColor(.sdsTertiaryText)
            }
        }
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
            LazyVStack(spacing: 0) {
                ForEach(filteredBookings) { booking in
                    BookingRow(
                        booking: booking,
                        isNewStudent: isNewStudent(booking),
                        isTicketPurchase: isTicketPurchase(booking),
                        scheduleText: scheduleText(for: booking)
                    )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedBooking = booking }

                    if booking.id != filteredBookings.last?.id {
                        Rectangle()
                            .fill(Color.sdsLightGreen)
                            .opacity(0.55)
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }
        }
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
        CourseMetricsEngine.isNewStudentBooking(booking, countByParticipant: bookingCountByParticipant)
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

private struct SummaryMetric: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(SDSType.agrandir(12, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(SDSType.agrandir(12))
                .foregroundColor(.sdsSecondaryText)
        }
    }
}

private enum PaymentFilter: CaseIterable, Hashable {
    case all
    case paid
    case unpaid
    case partial

    func title(paid: Int, unpaid: Int, partial: Int) -> String {
        switch self {
        case .all: "Alla"
        case .paid: "Betalda (\(paid))"
        case .unpaid: "Obetalda (\(unpaid))"
        case .partial: "Delbetalda (\(partial))"
        }
    }

    func matches(_ booking: Booking) -> Bool {
        switch self {
        case .all: true
        case .paid: booking.isPaid
        case .unpaid: booking.isUnpaid
        case .partial: booking.isPartiallyPaid
        }
    }
}

struct BookingRow: View {
    let booking: Booking
    let isNewStudent: Bool
    let isTicketPurchase: Bool
    let scheduleText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(booking.formattedCreatedDate)
                .font(SDSType.agrandir(12))
                .foregroundColor(.sdsMutedText)

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
                text: booking.paymentBadgeText,
                color: booking.paymentBadgeColor,
                textColor: booking.paymentTextColor
            )

            Text(booking.status?.displayName ?? "—")
                .font(SDSType.agrandir(12))
                .foregroundColor(.sdsSecondaryText)
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
            return "Betald · \(Int(amount)) \(payment?.currency ?? "SEK")"
        }

        if isPartiallyPaid {
            return "Delbetald · \(Int(payment?.amountPaid ?? 0)) \(payment?.currency ?? "SEK")"
        }

        if let due = payment?.paymentDue, !due.isEmpty {
            return "Obetald · förfaller \(due)"
        }

        return "Obetald"
    }

    var paymentBadgeColor: Color {
        if isPaid { return .sdsLightGreen }
        if isPartiallyPaid { return .sdsAmberSurface }
        return .sdsPinkSurface
    }

    var paymentTextColor: Color {
        if isPaid { return .sdsDarkGreen }
        if isPartiallyPaid { return .sdsWarningText }
        return .sdsPink
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
