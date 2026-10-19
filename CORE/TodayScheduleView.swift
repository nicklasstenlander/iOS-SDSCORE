import SwiftUI

struct TodayScheduleView: View {
    enum Mode {
        case admin
        case `public`
    }

    let mode: Mode
    @StateObject private var service = ScheduleService()
    @State private var isShowingDatePicker = false
    @State private var pickerDate = Date()
    @State private var hasScrolledForCurrentDate = false

    init(mode: Mode = .admin) {
        self.mode = mode
    }

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.timeZone = ScheduleService.stockholmTZ
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        dayNavigator
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)

                        if let error = service.errorMessage, !service.events.isEmpty {
                            errorBanner(error)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                        }

                        if service.isLoading && service.events.isEmpty {
                            loadingPlaceholder
                        } else if service.events.isEmpty {
                            emptyPlaceholder
                        } else {
                            eventCards
                        }
                    }
                }
                .onChange(of: service.displayedDate) { _, _ in
                    hasScrolledForCurrentDate = false
                }
                .onChange(of: service.events) { _, _ in
                    scrollToNowIfNeeded(proxy: proxy)
                }
            }
            .background(Color.sdsPageBackground.ignoresSafeArea())
            .navigationTitle(mode == .public ? "Dagens schema" : "Schema")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pickerDate = service.displayedDate
                        isShowingDatePicker = true
                    } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Välj datum")
                }
            }
            .refreshable {
                await service.loadSchedule(for: service.displayedDate)
            }
        }
        .onAppear { service.startPolling() }
        .onDisappear { service.stopPolling() }
        .sheet(isPresented: $isShowingDatePicker) {
            datePickerSheet
        }
    }

    // MARK: - Day Navigator

    private var dayNavigator: some View {
        HStack {
            navChevron(systemImage: "chevron.left") {
                service.navigateTo(
                    date: ScheduleService.stockholmCalendar.date(byAdding: .day, value: -1, to: service.displayedDate)
                        ?? service.displayedDate
                )
            }

            Spacer()

            HStack(spacing: 8) {
                Text(formattedHeaderDate)
                    .font(SDSType.agrandir(18, weight: .bold))
                    .foregroundColor(mode == .public ? .sdsTeal : .sdsDarkModeGreen)

                if !isToday {
                    todayButton
                }
            }

            Spacer()

            navChevron(systemImage: "chevron.right") {
                service.navigateTo(
                    date: ScheduleService.stockholmCalendar.date(byAdding: .day, value: 1, to: service.displayedDate)
                        ?? service.displayedDate
                )
            }
        }
    }

    private func navChevron(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color.sdsSurface)
                .foregroundColor(mode == .public ? .sdsTeal : .sdsDarkModeGreen)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.sdsBorder, lineWidth: 1))
        }
    }

    // Jämför med samma navigateTo som chevronerna använder, så isAutoTracking-beteendet vid midnatt förblir oförändrat
    private var todayButton: some View {
        Button {
            service.navigateTo(date: Date())
        } label: {
            Text("Idag")
                .font(SDSType.agrandir(13, weight: .bold))
                .foregroundColor(mode == .public ? .sdsTeal : .sdsDarkModeGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(mode == .public ? Color.sdsPublicSubtleSurface : Color.sdsLightGreenSurface)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var formattedHeaderDate: String {
        let raw = Self.headerFormatter.string(from: service.displayedDate)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private var datePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker("Välj datum", selection: $pickerDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(mode == .public ? .sdsTeal : .sdsAccent)

                Button {
                    pickerDate = Date()
                } label: {
                    Label("Idag", systemImage: "calendar.badge.clock")
                        .font(SDSType.agrandir(15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(mode == .public ? Color.sdsPublicSubtleSurface : Color.sdsLightGreenSurface)
                        .foregroundColor(mode == .public ? .sdsTeal : .sdsDarkModeGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color.sdsPageBackground.ignoresSafeArea())
            .navigationTitle("Välj datum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        isShowingDatePicker = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") {
                        service.navigateTo(date: pickerDate)
                        isShowingDatePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .environment(\.locale, Locale(identifier: "sv_SE"))
        .environment(\.timeZone, ScheduleService.stockholmTZ)
    }

    // MARK: - Event List

    private var eventCards: some View {
        LazyVStack(spacing: 12) {
            ForEach(service.events) { event in
                ScheduleEventCard(
                    event: event,
                    isOngoing: service.ongoingEvents.contains { $0.id == event.id },
                    isNext: service.ongoingEvents.isEmpty && service.nextEvent?.id == event.id,
                    mode: mode,
                    isPast: isToday && service.pastEventIDs.contains(event.id)
                )
                .id(event.id)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    private var isToday: Bool {
        ScheduleService.stockholmCalendar.isDate(service.displayedDate, inSameDayAs: Date())
    }

    // Scrolls to the first non-past pass once per viewing of today, so the user's own scrolling isn't overridden
    private func scrollToNowIfNeeded(proxy: ScrollViewProxy) {
        guard isToday, !hasScrolledForCurrentDate, !service.events.isEmpty else { return }
        hasScrolledForCurrentDate = true
        if let target = service.events.first(where: { !service.pastEventIDs.contains($0.id) })?.id {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    // MARK: - Empty / Loading States

    private var loadingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView().tint(mode == .public ? .sdsTeal : .sdsAccent)
            Text("Hämtar schema…")
                .font(SDSType.agrandir(15))
                .foregroundColor(.sdsMutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.minus")
                .font(.system(size: 44))
                .foregroundColor(.sdsMutedText)
                .padding(.bottom, 4)
            Text("Inga klasser idag")
                .font(SDSType.agrandir(18, weight: .bold))
                .foregroundColor(mode == .public ? .sdsTeal : .sdsDarkModeGreen)
            if mode == .public && service.errorMessage == nil {
                Text("Välj ett annat datum eller kika in igen senare.")
                    .font(SDSType.agrandir(14))
                    .foregroundColor(.sdsMutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if let error = service.errorMessage {
                Text(error)
                    .font(SDSType.agrandir(14))
                    .foregroundColor(.sdsMutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(SDSType.agrandir(13))
        }
        .foregroundColor(.sdsWarningText)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sdsAmberAdaptiveSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Event Card

struct ScheduleEventCard: View {
    let event: ScheduleEvent
    let isOngoing: Bool
    let isNext: Bool
    let mode: TodayScheduleView.Mode
    var isPast: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(timeParts.start)
                    .font(SDSType.agrandir(15, weight: .bold))
                    .foregroundColor(mode == .public ? .sdsTeal : .sdsDarkModeGreen)
                if !timeParts.end.isEmpty {
                    Text(timeParts.end)
                        .font(SDSType.agrandir(12))
                        .foregroundColor(.sdsSecondaryText)
                }
            }
            .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.name)
                    .font(SDSType.agrandir(16, weight: .bold))
                    .foregroundColor(mode == .public ? .sdsTeal : .sdsDarkModeGreen)
                    .lineLimit(1)

                if !teacherHallLine.isEmpty {
                    Text(teacherHallLine)
                        .font(SDSType.agrandir(13))
                        .foregroundColor(.sdsSecondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if mode == .admin && isOngoing {
                SDSBadge(
                    text: "Pågår nu",
                    color: .sdsDarkModeGreen,
                    textColor: Color.adaptive(light: "ffffff", dark: "1e4025")
                )
            } else if mode == .admin && isNext {
                SDSBadge(text: "Nästa", color: .sdsLightGreenSurface, textColor: .sdsDarkModeGreen)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(cardBorder, lineWidth: 1)
        )
        .opacity(isPast ? 0.55 : 1)
    }

    // Splits "16:30–17:45" (EN DASH) into start/end; falls back to the raw string if unparseable
    private var timeParts: (start: String, end: String) {
        let comps = event.time.components(separatedBy: "\u{2013}")
        guard comps.count == 2 else { return (event.time, "") }
        return (comps[0].trimmingCharacters(in: .whitespaces), comps[1].trimmingCharacters(in: .whitespaces))
    }

    private var placeDisplay: String {
        event.place.isEmpty ? "Övriga" : event.place
    }

    // "Matilda · Light Box" — omits the teacher segment when missing, never leaves a dangling separator
    private var teacherHallLine: String {
        var parts: [String] = []
        if !event.instructors.isEmpty { parts.append(event.instructors) }
        parts.append(placeDisplay)
        return parts.joined(separator: " · ")
    }

    private var cardBackground: Color {
        if mode == .public { return .sdsPublicSubtleSurface }
        if mode == .admin && isOngoing { return .sdsLightGreenSurface }
        if mode == .admin && isNext    { return Color.sdsLightGreenSurface.opacity(0.62) }
        return .sdsSurface
    }

    private var cardBorder: Color {
        if mode == .admin && isOngoing { return Color.sdsDarkGreen.opacity(0.25) }
        if mode == .admin && isNext    { return .sdsLightGreen }
        return mode == .public ? .sdsPublicBorder : .sdsBorder
    }
}

#Preview {
    TodayScheduleView()
}

#Preview("Passkort") {
    let mockEvents: [ScheduleEvent] = [
        ScheduleEvent(eventId: "0", eventCwId: "0", name: "Förskoledans 1-2", time: "15:30\u{2013}16:00", dayStr: "2026-10-15", instructors: "Elin", place: "Black Box", showing: true),
        ScheduleEvent(eventId: "1", eventCwId: "1", name: "Jazz & Balett 55+", time: "16:30\u{2013}17:15", dayStr: "2026-10-15", instructors: "Matilda", place: "Light Box", showing: true),
        ScheduleEvent(eventId: "2", eventCwId: "2", name: "Barndans 3-4", time: "16:30\u{2013}17:00", dayStr: "2026-10-15", instructors: "Elin", place: "Black Box", showing: true),
        ScheduleEvent(eventId: "3", eventCwId: "3", name: "Hiphop Teen", time: "17:15\u{2013}18:00", dayStr: "2026-10-15", instructors: "", place: "Light Box", showing: true)
    ]
    ScrollView {
        VStack(spacing: 12) {
            ForEach(mockEvents) { event in
                ScheduleEventCard(event: event, isOngoing: event.eventId == "1" || event.eventId == "2", isNext: false, mode: .admin, isPast: event.eventId == "0")
            }
            ForEach(mockEvents) { event in
                ScheduleEventCard(event: event, isOngoing: false, isNext: event.eventId == "3", mode: .public, isPast: event.eventId == "0")
            }
        }
        .padding(20)
    }
    .background(Color.sdsPageBackground.ignoresSafeArea())
}
