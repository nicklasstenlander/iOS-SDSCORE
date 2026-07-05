import SwiftUI

struct AnmalningarView: View {
    @EnvironmentObject var cogWork: CogWorkService
    @State private var searchText = ""
    @State private var paymentFilter = PaymentFilter.all
    @State private var selectedPeriod = Periods.defaultFullPeriodLabel()
    @State private var selectedBooking: Booking?

    private var periods: [String] {
        var values = Set(cogWork.bookings.compactMap(\.periodLabel))
        values.insert(Periods.defaultFullPeriodLabel())
        return ["Alla terminer"] + values.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
    }

    private var filteredBookings: [Booking] {
        periodBookings.filter { booking in
            let matchesPeriod = selectedPeriod == "Alla terminer" || booking.periodLabel == selectedPeriod
            let matchesSearch = searchText.isEmpty
                || (booking.participant?.name?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (booking.event?.name?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesPayment = paymentFilter.matches(booking)
            return matchesPeriod && matchesSearch && matchesPayment
        }
        .sorted {
            $0.created.localizedStandardCompare($1.created) == .orderedDescending
        }
    }

    private var periodBookings: [Booking] {
        cogWork.bookings.filter { selectedPeriod == "Alla terminer" || $0.periodLabel == selectedPeriod }
    }

    private var paidCount: Int { periodBookings.filter(\.isPaid).count }
    private var unpaidCount: Int { periodBookings.filter(\.isUnpaid).count }
    private var partialCount: Int { periodBookings.filter(\.isPartiallyPaid).count }

    private var bookingCountByParticipant: [String: Int] {
        CourseMetricsEngine.countBookingsByParticipant(cogWork.bookings)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    filterScroller(periods) { period in
                        SDSPill(title: period, isSelected: selectedPeriod == period) {
                            selectedPeriod = period
                        }
                    }

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
                await cogWork.forceRefreshFromCogWork()
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
            if cogWork.bookings.isEmpty {
                await cogWork.loadBookings()
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
                .font(SDSType.rounded(15))
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
                Button {
                    Task { await cogWork.forceRefreshFromCogWork() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.sdsDarkModeGreen)
                .accessibilityLabel("Hämta ny data")
            }
        }
    }

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summaryTitle)
                .font(SDSType.rounded(14, weight: .bold))
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
                    .font(SDSType.rounded(11))
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
                .font(SDSType.rounded(15, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 220)
        } else if filteredBookings.isEmpty {
            Text("Inga anmälningar hittades")
                .font(SDSType.rounded(15, weight: .bold))
                .foregroundColor(.sdsMutedText)
                .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(filteredBookings) { booking in
                    BookingRow(booking: booking, isNewStudent: isNewStudent(booking))
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
                .font(SDSType.rounded(12, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(SDSType.rounded(12))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(booking.formattedCreatedDate)
                .font(SDSType.rounded(12))
                .foregroundColor(.sdsMutedText)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(booking.participant?.name ?? "Okänd deltagare")
                            .font(SDSType.rounded(16, weight: .bold))
                            .foregroundColor(.sdsPrimaryText)
                            .lineLimit(2)

                        if isNewStudent {
                            SDSBadge(text: "Ny elev")
                        }
                    }

                    Text(booking.event?.name ?? "Okänd kurs")
                        .font(SDSType.rounded(14))
                        .foregroundColor(.sdsSecondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 10)

                Text(booking.formattedPrice)
                    .font(SDSType.rounded(15, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
                    .multilineTextAlignment(.trailing)
            }

            SDSBadge(
                text: booking.paymentBadgeText,
                color: booking.paymentBadgeColor,
                textColor: booking.paymentTextColor
            )

            Text(booking.status?.displayName ?? "—")
                .font(SDSType.rounded(12))
                .foregroundColor(.sdsSecondaryText)
        }
        .padding(16)
        .background(Color.sdsElevatedSurface)
    }
}

struct BookingDetailSheet: View {
    let booking: Booking
    let relatedBookings: [Booking]
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DELTAGARE")
                            .font(SDSType.rounded(12, weight: .bold))
                            .foregroundColor(.sdsMidGreen)
                        Text(booking.participant?.name ?? "Okänd deltagare")
                            .font(SDSType.rounded(30, weight: .bold))
                            .foregroundColor(.sdsPrimaryText)
                    }

                    VStack(spacing: 18) {
                        DetailInfoRow(icon: "calendar", label: "Födelsedag", value: booking.participant?.dateOfBirth ?? "Saknas i bokningsdatan")
                        DetailInfoRow(icon: "envelope", label: "E-post", value: "Saknas i bokningsdatan")
                        DetailInfoRow(icon: "phone", label: "Telefon", value: "Saknas i bokningsdatan")
                        DetailInfoRow(icon: "mappin.and.ellipse", label: "Adress", value: "Saknas i bokningsdatan")
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "book.closed")
                                .foregroundColor(.sdsDarkGreen)
                            Text("KURSER")
                                .font(SDSType.rounded(12, weight: .bold))
                                .foregroundColor(.sdsMidGreen)
                        }

                        VStack(spacing: 0) {
                            ForEach(relatedBookings.isEmpty ? [booking] : relatedBookings) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.event?.name ?? "Okänd kurs")
                                        .font(SDSType.rounded(16, weight: .bold))
                                        .foregroundColor(.sdsText)
                                    Text(item.status?.name ?? "Accepterad")
                                        .font(SDSType.rounded(14))
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stäng") { dismiss() }
                        .font(SDSType.rounded(15, weight: .bold))
                        .foregroundColor(.sdsDarkGreen)
                }
            }
        }
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
                    .font(SDSType.rounded(11, weight: .bold))
                    .foregroundColor(.sdsMidGreen)
                Text(value)
                    .font(SDSType.rounded(15))
                    .foregroundColor(.sdsText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private extension Booking {
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
