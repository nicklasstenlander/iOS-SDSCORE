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

            Text(formattedHeaderDate)
                .font(SDSType.agrandir(18, weight: .bold))
                .foregroundColor(mode == .public ? .sdsTeal : .sdsDarkModeGreen)

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
                    .tint(.sdsDarkModeGreen)

                Button {
                    pickerDate = Date()
                } label: {
                    Label("Idag", systemImage: "calendar.badge.clock")
                        .font(SDSType.agrandir(15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.sdsLightGreenSurface)
                        .foregroundColor(.sdsDarkModeGreen)
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
                    isOngoing: service.ongoingEvent?.id == event.id,
                    isNext: service.ongoingEvent == nil && service.nextEvent?.id == event.id,
                    mode: mode
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    // MARK: - Empty / Loading States

    private var loadingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.sdsDarkModeGreen)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mode == .admin && isOngoing {
                SDSBadge(
                    text: "Pågår nu",
                    color: .sdsDarkModeGreen,
                    textColor: Color.adaptive(light: "ffffff", dark: "1e4025")
                )
            } else if mode == .admin && isNext {
                SDSBadge(text: "Nästa", color: .sdsLightGreenSurface, textColor: .sdsDarkModeGreen)
            }

            Text(event.name)
                .font(SDSType.agrandir(16, weight: .bold))
                .foregroundColor(mode == .public ? .sdsTeal : .sdsDarkModeGreen)

            VStack(alignment: .leading, spacing: 5) {
                Label(event.time, systemImage: "clock")
                    .font(SDSType.agrandir(14))
                    .foregroundColor(.sdsSecondaryText)

                if !event.instructors.isEmpty {
                    Label(event.instructors, systemImage: "person")
                        .font(SDSType.agrandir(14))
                        .foregroundColor(.sdsSecondaryText)
                }

                Label(placeDisplay, systemImage: "mappin")
                    .font(SDSType.agrandir(14))
                    .foregroundColor(.sdsSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var placeDisplay: String {
        event.place.isEmpty ? "Övriga" : event.place
    }

    private var cardBackground: Color {
        if mode == .admin && isOngoing { return .sdsLightGreenSurface }
        if mode == .admin && isNext    { return Color.sdsLightGreenSurface.opacity(0.62) }
        return .sdsSurface
    }

    private var cardBorder: Color {
        if mode == .admin && isOngoing { return Color.sdsDarkGreen.opacity(0.25) }
        if mode == .admin && isNext    { return .sdsLightGreen }
        return .sdsBorder
    }
}

#Preview {
    TodayScheduleView()
}
