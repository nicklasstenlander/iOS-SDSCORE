import Foundation
import Combine

@MainActor
final class CogWorkService: ObservableObject {
    private let baseURL = "https://sds-cogwork-proxy.nicklas-stenlander.workers.dev"

    @Published var bookings: [Booking] = []
    @Published var events: [Event] = []
    @Published var duplicateBookings: [Booking] = []
    @Published var users: [CogWorkUser] = []
    @Published var selectedUserBookings: [Booking] = []
    @Published var isLoading = false
    @Published var isLoadingEvents = false
    @Published var isLoadingUsers = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var selectedPeriod = Periods.defaultPeriod() {
        didSet { if oldValue != selectedPeriod { recomputeDerivedValues() } }
    }

    private var lastFetch: Date?
    private let cacheLifetime: TimeInterval = 300

    /// Hämtar all data om cachen är äldre än 5 min eller om data saknas. Anropa force: true för pull-to-refresh.
    func loadAllDataIfNeeded(force: Bool = false) async {
        if !force {
            guard !isLoading else { return }
            if let last = lastFetch,
               Date().timeIntervalSince(last) < cacheLifetime,
               !bookings.isEmpty {
                return
            }
        }
        await loadAllData()
    }

    /// Hämtar alla bokningar (aggregerat över terminer via Workerns cache).
    func loadBookings() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await proxyData(queryItems: [URLQueryItem(name: "type", value: "bookings")])
            let decoded = try JSONDecoder().decode(BookingsResponse.self, from: data)
            bookings = decoded.bookings
            lastUpdated = Date()
            recomputeDerivedValues()
        } catch {
            errorMessage = "Kunde inte hämta anmälningar. \(Self.readableErrorMessage(error))"
        }
    }

    func loadAllData(eventBlockId: String? = nil) async {
        isLoading = true
        isLoadingEvents = true
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingEvents = false
        }

        do {
            var queryItems = [URLQueryItem(name: "type", value: "all")]
            if let eventBlockId, !eventBlockId.isEmpty {
                queryItems.append(URLQueryItem(name: "eventBlockId", value: eventBlockId))
            }
            let data = try await proxyData(queryItems: queryItems)
            let decoded = try JSONDecoder().decode(AllDataResponse.self, from: data)
            bookings = decoded.bookings.bookings
            events = decoded.events?.events ?? []
            duplicateBookings = decoded.duplicates?.bookings ?? []
            lastUpdated = Date()
            lastFetch = Date()
            recomputeDerivedValues()
        } catch is CancellationError {
            // Task cancelled by SwiftUI lifecycle — not a user-visible error
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession cancelled by task lifecycle — not a user-visible error
        } catch {
            errorMessage = "Kunde inte hämta översiktsdata. \(Self.readableErrorMessage(error))"
        }
    }

    func loadEvents(eventBlockId: String? = nil) async {
        isLoadingEvents = true
        errorMessage = nil
        defer { isLoadingEvents = false }

        do {
            var queryItems = [URLQueryItem(name: "type", value: "all")]
            if let eventBlockId, !eventBlockId.isEmpty {
                queryItems.append(URLQueryItem(name: "eventBlockId", value: eventBlockId))
            }
            let data = try await proxyData(queryItems: queryItems)
            let decoded = try JSONDecoder().decode(AllDataResponse.self, from: data)
            events = decoded.events?.events ?? []
            recomputeDerivedValues()
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            errorMessage = "Kunde inte hämta kurser. \(Self.readableErrorMessage(error))"
        }
    }

    func searchUsers(query: String) async {
        isLoadingUsers = true
        errorMessage = nil
        defer { isLoadingUsers = false }

        do {
            let response: UsersResponse = try await staffAPI(path: "users", extra: [
                "textSearch": query,
                "maxRows": "50"
            ])
            users = response.users
        } catch {
            errorMessage = "Kunde inte söka kunder. \(Self.readableErrorMessage(error))"
        }
    }

    func loadUser(named name: String) async -> CogWorkUser? {
        isLoadingUsers = true
        errorMessage = nil
        defer { isLoadingUsers = false }

        do {
            let response: UsersResponse = try await staffAPI(path: "users", extra: [
                "name": name
            ])
            return response.users.first
        } catch {
            errorMessage = "Kunde inte hämta kund. \(Self.readableErrorMessage(error))"
            return nil
        }
    }

    func loadBookings(forUserId userId: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: BookingsResponse = try await staffAPI(path: "bookings", extra: [
                "userId": String(userId)
            ])
            selectedUserBookings = response.bookings
        } catch {
            errorMessage = "Kunde inte hämta deltagarens bokningar. \(Self.readableErrorMessage(error))"
        }
    }

    /// Tvingar Workern att rensa cache och hämta färskt från CogWork ("Från CogWork"-knappen).
    /// Admin-only: cachen delas av alla användare, så en felaktig rensning påverkar alla.
    func forceRefreshFromCogWork() async {
        guard SupabaseAuthService.shared.isAdmin else {
            errorMessage = "Saknar behörighet för detta."
            return
        }

        isLoading = true
        isLoadingEvents = true
        errorMessage = nil
        defer { isLoading = false }
        defer { isLoadingEvents = false }

        URLCache.shared.removeAllCachedResponses()

        do {
            try await purgeProxyCache()
            let data = try await proxyData(queryItems: [URLQueryItem(name: "type", value: "all")])
            let decoded = try JSONDecoder().decode(AllDataResponse.self, from: data)
            bookings = decoded.bookings.bookings
            events = decoded.events?.events ?? []
            duplicateBookings = decoded.duplicates?.bookings ?? []
            lastUpdated = Date()
            lastFetch = Date()
            recomputeDerivedValues()
        } catch {
            errorMessage = "Kunde inte rensa cache och hämta ny data. \(Self.readableErrorMessage(error))"
        }
    }

    // MARK: - Cachade härledda värden (beräknas en gång vid dataändring/periodbyte)

    @Published private(set) var periodBookings: [Booking] = []
    @Published private(set) var statisticalPeriodBookings: [Booking] = []
    @Published private(set) var statisticalPeriodEvents: [Event] = []
    @Published private(set) var eventLookup: [String: Event] = [:]
    @Published private(set) var bookingCountByParticipant: [String: Int] = [:]
    @Published private(set) var courseChangesByParticipant: [String: ParticipantCourseChange] = [:]

    private func recomputeDerivedValues() {
        let lookup: [String: Event] = events.reduce(into: [:]) { result, event in
            var keys = [String(event.id)]
            if let key = event.key, !key.isEmpty { keys.append(key) }
            for key in keys where result[key] == nil { result[key] = event }
        }
        eventLookup = lookup
        periodBookings = bookings.filter { Periods.matches($0, period: selectedPeriod) }
        statisticalPeriodBookings = periodBookings.filter {
            CourseMetricsEngine.isStatisticalBooking($0, eventLookup: lookup)
        }
        statisticalPeriodEvents = events.filter {
            Periods.matches($0, period: selectedPeriod) && CourseMetricsEngine.isStatisticalEvent($0)
        }
        bookingCountByParticipant = CourseMetricsEngine.countBookingsByParticipant(bookings, eventLookup: lookup)
        courseChangesByParticipant = CourseMetricsEngine.courseChangesByParticipant(
            bookings: bookings,
            currentPeriodCode: selectedPeriod.codePrefix,
            eventLookup: lookup
        )
    }

    var totalCount: Int { statisticalPeriodBookings.count }

    var paidCount: Int { statisticalPeriodBookings.filter { $0.payment?.paid == true }.count }

    var unpaidCount: Int { statisticalPeriodBookings.filter { $0.payment?.paid == false }.count }

    /// Antal kurser (event) i vald period — matchar webbens "Aktiva kurser".
    var periodEventCount: Int {
        statisticalPeriodEvents.count
    }

    /// Kombinerat antal ärenden som kräver manuell hantering (NEW-status + dubbelanmälda).
    /// Matchar webbens `alerts.length` i Dashboard.
    var pendingReviewCount: Int {
        let newCount = statisticalPeriodBookings.filter(\.isPendingReviewForOverview).count
        return newCount + duplicateCount
    }

    /// Deduplicerat antal dubbelanmälningar i vald period. Exponerad (inte privat) så att
    /// OversiktView kan visa den separat från pendingReviewCount, som redan summerar in den.
    var duplicateCount: Int {
        let lookup = eventLookup
        let excludedEventIds = Set(
            events.compactMap { event -> Int? in
                CourseMetricsEngine.isPerformance(event: event) ? event.id : nil
            }
        )

        var seenParticipants = Set<String>()
        var seenBookings = Set<String>()
        var count = 0
        let grouped = Dictionary(grouping: duplicateBookings) { b -> String in
            let pKey = b.participant?.key ?? b.participant?.id.map(String.init) ?? ""
            let eId = b.event?.id.map(String.init) ?? ""
            return "\(pKey)::\(eId)"
        }
        for (_, group) in grouped {
            guard group.count > 1, let first = group.first else { continue }
            if CourseMetricsEngine.isPerformance(booking: first, eventLookup: lookup) { continue }
            if let eId = first.event?.id, excludedEventIds.contains(eId) { continue }
            let pKey = first.participant?.key ?? first.participant?.id.map(String.init) ?? ""
            guard !pKey.isEmpty, !seenParticipants.contains(pKey) else { continue }
            seenParticipants.insert(pKey)
            if !seenBookings.contains(first.key) {
                seenBookings.insert(first.key)
                count += 1
            }
        }
        return count
    }

    /// Medelbeläggning i procent för vald period.
    /// Formel: summa statistics.accepted / summa maxParticipants, begränsat till events med kapacitetsgräns.
    var avgOccupancyPercent: Int? {
        let eventsWithCapacity = statisticalPeriodEvents.filter { ($0.requirements?.maxParticipants ?? 0) > 0 }
        guard !eventsWithCapacity.isEmpty else { return nil }

        let totalMax = eventsWithCapacity.compactMap { $0.requirements?.maxParticipants }.reduce(0, +)
        guard totalMax > 0 else { return nil }

        let acceptedBookings = statisticalPeriodBookings.filter(\.isAcceptedForOverview)
        let totalAccepted = eventsWithCapacity.reduce(0) { acc, event in
            let eventKeys = Set([String(event.id), event.key].compactMap { $0 })
            let accepted = acceptedBookings.filter { booking in
                let bookingKeys = [booking.event?.id.map(String.init), booking.event?.key].compactMap { $0 }
                return bookingKeys.contains { eventKeys.contains($0) }
            }.count
            return acc + (accepted > 0 ? accepted : (event.statistics?.accepted ?? 0))
        }

        return Int((Double(totalAccepted) / Double(totalMax) * 100).rounded())
    }

    /// Hämtar data via Workern (sds-cogwork-proxy) med Supabase-JWT. Används för
    /// de kombinerade `/?type=...`-rutterna som STAFF har tillgång till.
    private func proxyData(queryItems: [URLQueryItem]) async throws -> Data {
        guard let url = URL(string: baseURL + "/") else {
            throw URLError(.badURL)
        }

        var request = try APIClient.request(url: url, queryItems: queryItems)
        // Vanliga apphämtningar ska ta senaste svaret från Cloudflare Proxy,
        // men inte tvinga Workern att gå hela vägen till CogWork.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        return try await APIClient.data(for: request)
    }

    private func purgeProxyCache() async throws {
        guard let purgeURL = URL(string: "\(baseURL)/purge") else {
            throw URLError(.badURL)
        }

        var request = try APIClient.request(url: purgeURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        _ = try await APIClient.data(for: request)
    }

    /// Hämtar kund-/bokningsdata via Workerns STAFF-skyddade `/cogwork/<path>`-rutter.
    private func staffAPI<T: Decodable>(
        path: String,
        extra: [String: String] = [:]
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)/cogwork/\(path)") else {
            throw URLError(.badURL)
        }

        let queryItems = extra
            .filter { !$0.value.isEmpty }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        let request = try APIClient.request(url: url, queryItems: queryItems)
        return try await APIClient.json(T.self, for: request)
    }
}

private extension CogWorkService {
    static func readableErrorMessage(_ error: Error) -> String {
        if let apiError = error as? APIClientError {
            return apiError.localizedDescription
        }
        return readableDecodingError(error)
    }

    static func readableDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }

        switch decodingError {
        case .keyNotFound(let key, let context):
            return "Saknar fält \(path(context.codingPath + [key]))."
        case .typeMismatch(_, let context):
            return "Fel datatyp vid \(path(context.codingPath)). \(context.debugDescription)"
        case .valueNotFound(_, let context):
            return "Saknar värde vid \(path(context.codingPath))."
        case .dataCorrupted(let context):
            return "Ogiltig data vid \(path(context.codingPath)). \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    static func path(_ codingPath: [CodingKey]) -> String {
        let value = codingPath.map(\.stringValue).joined(separator: ".")
        return value.isEmpty ? "rot" : value
    }
}
