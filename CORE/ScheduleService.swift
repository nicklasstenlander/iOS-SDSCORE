import Foundation
import Combine

private let scheduleProxyURL = "https://script.google.com/macros/s/AKfycbx-euNjfAQaEfgA2xpkmhYUgpxUOI29cw0GF3-aLRkLowr4-U40HGdXyKgQPyFOCtyo/exec"

@MainActor
final class ScheduleService: ObservableObject {
    static let stockholmTZ = TimeZone(identifier: "Europe/Stockholm")!
    static let stockholmCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = stockholmTZ
        calendar.locale = Locale(identifier: "sv_SE")
        return calendar
    }()

    @Published var events: [ScheduleEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var displayedDate = Date()
    @Published var ongoingEvent: ScheduleEvent?
    @Published var nextEvent: ScheduleEvent?

    private var fetchPollTask: Task<Void, Never>?
    private var localTimerTask: Task<Void, Never>?
    private var lastFetchedDateString = ""
    // Tracks whether the user has manually navigated; suppresses midnight auto-rollover when true
    private var isAutoTracking = true

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = stockholmTZ
        return f
    }()

    // Parses naive local datetime strings; timezone set explicitly to Europe/Stockholm
    private static let eventTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = stockholmTZ
        return f
    }()

    func startPolling() {
        let todayStr = Self.dayFormatter.string(from: Date())
        if lastFetchedDateString != todayStr {
            Task { await loadSchedule(for: displayedDate) }
        }
        startFetchPoll()
        startLocalTimer()
    }

    func stopPolling() {
        fetchPollTask?.cancel()
        fetchPollTask = nil
        localTimerTask?.cancel()
        localTimerTask = nil
    }

    func navigateTo(date: Date) {
        isAutoTracking = false
        displayedDate = date
        Task { await loadSchedule(for: date) }
    }

    func loadSchedule(for date: Date) async {
        let dateStr = Self.dayFormatter.string(from: date)
        isLoading = true
        defer { isLoading = false }

        var comps = URLComponents(string: scheduleProxyURL)!
        comps.queryItems = [
            URLQueryItem(name: "action", value: "events_by_date"),
            URLQueryItem(name: "date", value: dateStr)
        ]
        guard let url = comps.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Serverfel vid hämtning av schema."
                return
            }
            let decoded = try JSONDecoder().decode([ScheduleEvent].self, from: data)
            events = decoded.sorted { startTime(of: $0) < startTime(of: $1) }
            lastFetchedDateString = dateStr
            errorMessage = nil
            recomputeCurrentStatus()
        } catch {
            print("[ScheduleService] Nätverksfel: \(error.localizedDescription)")
            errorMessage = "Kunde inte hämta schema."
            // Retain existing events — do NOT clear on network error
        }
    }

    func recomputeCurrentStatus() {
        let now = Date()
        let timed = events.compactMap { parseEventTimes($0) }

        // Among overlapping ongoing events, keep the one that started most recently
        ongoingEvent = timed
            .filter { $0.1 <= now && now < $0.2 }
            .max(by: { $0.1 < $1.1 })
            .map { $0.0 }

        nextEvent = timed
            .filter { $0.1 > now }
            .min(by: { $0.1 < $1.1 })
            .map { $0.0 }
    }

    // Returns (event, startDate, endDate), or nil and logs if the time string is malformed
    private func parseEventTimes(_ event: ScheduleEvent) -> (ScheduleEvent, Date, Date)? {
        // Split on U+2013 EN DASH, NOT on U+002D HYPHEN-MINUS
        let parts = event.time.components(separatedBy: "\u{2013}")
        guard parts.count == 2 else {
            print("[ScheduleService] Ogiltigt tidsformat för event '\(event.eventId)': '\(event.time)'")
            return nil
        }
        let startStr = parts[0].trimmingCharacters(in: .whitespaces)
        let endStr   = parts[1].trimmingCharacters(in: .whitespaces)
        // Naive datetime strings — timezone applied via eventTimeFormatter (Europe/Stockholm)
        let startISO = "\(event.dayStr)T\(startStr):00"
        let endISO   = "\(event.dayStr)T\(endStr):00"
        guard
            let start = Self.eventTimeFormatter.date(from: startISO),
            let end   = Self.eventTimeFormatter.date(from: endISO)
        else {
            print("[ScheduleService] Kunde inte parsa tider för event '\(event.eventId)': '\(startISO)' / '\(endISO)'")
            return nil
        }
        return (event, start, end)
    }

    private func startTime(of event: ScheduleEvent) -> Date {
        parseEventTimes(event).map { $0.1 } ?? .distantFuture
    }

    private func startFetchPoll() {
        fetchPollTask?.cancel()
        fetchPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300)) // 5-minute network poll
                guard !Task.isCancelled else { return }
                await loadSchedule(for: displayedDate)
            }
        }
    }

    private func startLocalTimer() {
        localTimerTask?.cancel()
        localTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15)) // local recompute every 15 s
                guard !Task.isCancelled else { return }
                recomputeCurrentStatus()
                checkDateRollover()
            }
        }
    }

    private func checkDateRollover() {
        guard isAutoTracking, !lastFetchedDateString.isEmpty else { return }
        let todayStr = Self.dayFormatter.string(from: Date())
        guard lastFetchedDateString != todayStr else { return }
        displayedDate = Date()
        Task { await loadSchedule(for: displayedDate) }
    }
}
