import SwiftUI

struct ContentCardEditorView: View {
    let card: ContentCard?
    let onSaved: (ContentCard) -> Void
    let onDeleted: (String) -> Void

    @EnvironmentObject private var cogWork: CogWorkService
    @EnvironmentObject private var rideau: RideauEventsService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = ContentCardsService()
    @State private var draft: ContentCardDraft
    @State private var linkDestinationType: ContentCardLinkDestinationType
    @State private var selectedEventId: Int?
    @State private var selectedPerformanceSlug: String?
    @State private var hasExpiry: Bool
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showsDeleteConfirmation = false
    @State private var errorMessage: String?

    init(card: ContentCard?, onSaved: @escaping (ContentCard) -> Void, onDeleted: @escaping (String) -> Void) {
        self.card = card
        self.onSaved = onSaved
        self.onDeleted = onDeleted

        if let card {
            let starts = Self.parseDate(card.startsAt) ?? Date()
            let expires = card.expiresAt.flatMap { Self.parseDate($0) }
            let destination = card.appDestination?.trimmingCharacters(in: .whitespacesAndNewlines)
            let initialLinkDestinationType = Self.linkDestinationType(for: destination)
            let initialSelectedEventId = Self.selectedEventId(from: destination)
            let initialSelectedPerformanceSlug = Self.selectedPerformanceSlug(from: destination)
            _draft = State(initialValue: ContentCardDraft(
                type: card.type,
                title: card.title,
                body: card.body ?? "",
                imageUrl: card.imageUrl ?? "",
                linkUrl: card.linkUrl ?? "",
                linkLabel: card.linkLabel ?? "",
                appDestination: destination?.isEmpty == false ? destination : nil,
                startsAt: starts,
                expiresAt: expires,
                published: card.published,
                sortOrder: card.sortOrder,
                sendPush: card.sendPush ?? false,
                showOnWeb: card.showOnWeb,
                showOnApp: card.showOnApp
            ))
            _linkDestinationType = State(initialValue: initialLinkDestinationType)
            _selectedEventId = State(initialValue: initialSelectedEventId)
            _selectedPerformanceSlug = State(initialValue: initialSelectedPerformanceSlug)
            _hasExpiry = State(initialValue: card.expiresAt != nil)
        } else {
            _draft = State(initialValue: ContentCardDraft())
            _linkDestinationType = State(initialValue: .external)
            _selectedEventId = State(initialValue: nil)
            _selectedPerformanceSlug = State(initialValue: nil)
            _hasExpiry = State(initialValue: false)
        }
    }

    var body: some View {
        List {
            errorSection
            settingsSection
            pushSection
            contentSection
            datesSection
            saveSection
            deleteSection
        }
        .font(SDSType.agrandir(15))
        .navigationTitle(card == nil ? "Nytt kort" : "Redigera kort")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Radera kort?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Ja, radera permanent", role: .destructive) {
                Task { await deleteCard() }
            }
            Button("Avbryt", role: .cancel) { }
        } message: {
            Text("Detta går inte att ångra. Kortet tas bort permanent.")
        }
        .scrollContentBackground(.hidden)
        .background(Color.sdsPageBackground)
        .task {
            if cogWork.events.isEmpty {
                await cogWork.loadEvents()
            }
            await rideau.loadIfNeeded()
        }
        .onChange(of: linkDestinationType) { _, _ in
            syncLinkDestination()
        }
        .onChange(of: selectedEventId) { _, _ in
            syncLinkDestination()
        }
        .onChange(of: selectedPerformanceSlug) { _, _ in
            syncLinkDestination()
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .font(SDSType.agrandir(13, weight: .bold))
                    .foregroundColor(.sdsPink)
            }
            .listRowBackground(Color.sdsPinkAdaptiveSurface)
        }
    }

    private var settingsSection: some View {
        Section("Inställningar") {
            Picker("Typ", selection: $draft.type) {
                Text("Nyhet").tag("news")
                Text("Event").tag("event")
                Text("Utvald kurs").tag("featured_course")
                Text("Banner").tag("banner")
            }
            .pickerStyle(.menu)
            .tint(.sdsAccent)
            .font(SDSType.agrandir(15))

            Toggle("Publicerad", isOn: $draft.published)
                .font(SDSType.agrandir(14, weight: .bold))
                .tint(.sdsAccent)

            Toggle("Visa på webben", isOn: $draft.showOnWeb)
                .font(SDSType.agrandir(14))
                .tint(.sdsAccent)

            Toggle("Visa i appen", isOn: $draft.showOnApp)
                .font(SDSType.agrandir(14))
                .tint(.sdsAccent)

            Stepper("Sorteringsordning: \(draft.sortOrder)", value: $draft.sortOrder, in: 0...999)
                .font(SDSType.agrandir(14))
        }
    }

    @ViewBuilder
    private var pushSection: some View {
        let isSent = card?.pushSentAt != nil
        Section {
            if isSent {
                if let sentStr = card?.pushSentAt, let formatted = formatPushSentTime(sentStr) {
                    Label("Notis skickad \(formatted)", systemImage: "checkmark.circle.fill")
                        .font(SDSType.agrandir(14))
                        .foregroundColor(.sdsDarkModeGreen)
                } else {
                    Label("Notis redan skickad", systemImage: "checkmark.circle.fill")
                        .font(SDSType.agrandir(14))
                        .foregroundColor(.sdsDarkModeGreen)
                }
            } else {
                Toggle("Skicka pushnotis när kortet publiceras", isOn: $draft.sendPush)
                    .font(SDSType.agrandir(14))
                    .tint(.sdsAccent)
            }
        } header: {
            Text("Pushnotis")
        } footer: {
            if !isSent {
                Text("Notisen skickas inom ~15 minuter efter publicering.")
            }
        }
    }

    private var contentSection: some View {
        Section("Innehåll") {
            TextField("Titel (obligatorisk)", text: $draft.title)
                .font(SDSType.agrandir(15))

            TextField("Text", text: $draft.body, axis: .vertical)
                .font(SDSType.agrandir(15))
                .lineLimit(3...8)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Bild-URL", text: $draft.imageUrl)
                    .font(SDSType.agrandir(15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                let trimmedImageUrl = draft.imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedImageUrl.isEmpty, let url = URL(string: trimmedImageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            Label("Bilden kunde inte laddas", systemImage: "exclamationmark.triangle")
                                .font(SDSType.agrandir(13))
                                .foregroundColor(.sdsPink)
                        case .empty:
                            ProgressView()
                                .tint(.sdsAccent)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }

            Picker("Länk-typ", selection: $linkDestinationType) {
                ForEach(ContentCardLinkDestinationType.allCases) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.menu)
            .tint(.sdsAccent)
            .font(SDSType.agrandir(15))

            if linkDestinationType == .external {
                TextField("Länk-URL", text: $draft.linkUrl)
                    .font(SDSType.agrandir(15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } else if linkDestinationType == .specificCourse {
                CourseEventPicker(title: "Kurs", selectedEventId: $selectedEventId)
            } else if linkDestinationType == .specificPerformance {
                PerformanceEventPicker(selectedSlug: $selectedPerformanceSlug)
            }

            TextField("Länktext (t.ex. Anmäl dig)", text: $draft.linkLabel)
                .font(SDSType.agrandir(15))
        }
    }

    private var datesSection: some View {
        Section("Datum") {
            DatePicker(
                "Visas från",
                selection: $draft.startsAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(SDSType.agrandir(14))
            .tint(.sdsAccent)

            Toggle("Slutdatum", isOn: $hasExpiry)
                .font(SDSType.agrandir(14))
                .tint(.sdsAccent)
                .onChange(of: hasExpiry) { _, newValue in
                    if newValue && draft.expiresAt == nil {
                        draft.expiresAt = Calendar.current.date(byAdding: .month, value: 1, to: Date())
                    } else if !newValue {
                        draft.expiresAt = nil
                    }
                }

            if hasExpiry {
                DatePicker(
                    "Visas till",
                    selection: Binding(
                        get: { draft.expiresAt ?? Date() },
                        set: { draft.expiresAt = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(SDSType.agrandir(14))
                .tint(.sdsAccent)
            }
        }
    }

    private var saveSection: some View {
        let titleEmpty = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let missingCourse = linkDestinationType == .specificCourse && selectedEventId == nil
        let missingPerformance = linkDestinationType == .specificPerformance && selectedPerformanceSlug == nil
        return Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView()
                            .tint(.sdsAccent)
                    } else {
                        Text("Spara")
                            .font(SDSType.agrandir(17, weight: .bold))
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .disabled(isSaving || isDeleting || titleEmpty || missingCourse || missingPerformance)
            .listRowBackground(titleEmpty || missingCourse || missingPerformance ? Color.sdsSubtleSurface : Color.sdsAccent)
            .foregroundColor(titleEmpty || missingCourse || missingPerformance ? .sdsSecondaryText : .white)
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        if card != nil {
            Section {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text(isDeleting ? "Raderar..." : "Radera kort")
                            .font(SDSType.agrandir(15, weight: .bold))
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isSaving || isDeleting)
            } header: {
                Text("Farlig åtgärd")
            } footer: {
                Text("Radering tar bort kortet permanent. Använd bara detta när du är säker.")
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        var draftToSave = draft
        if !hasExpiry {
            draftToSave.expiresAt = nil
        }
        syncLinkDestination(on: &draftToSave)

        do {
            if let card {
                try await service.updateCard(id: card.id, draftToSave)
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime]
                let updated = ContentCard(
                    id: card.id,
                    type: draftToSave.type,
                    title: draftToSave.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    body: emptyToNil(draftToSave.body),
                    imageUrl: emptyToNil(draftToSave.imageUrl),
                    linkUrl: emptyToNil(draftToSave.linkUrl),
                    linkLabel: emptyToNil(draftToSave.linkLabel),
                    appDestination: draftToSave.appDestination,
                    startsAt: iso.string(from: draftToSave.startsAt),
                    expiresAt: draftToSave.expiresAt.map { iso.string(from: $0) },
                    published: draftToSave.published,
                    sortOrder: draftToSave.sortOrder,
                    sendPush: draftToSave.sendPush,
                    pushSentAt: card.pushSentAt,
                    showOnWeb: draftToSave.showOnWeb,
                    showOnApp: draftToSave.showOnApp
                )
                onSaved(updated)
            } else {
                let created = try await service.createCard(draftToSave)
                onSaved(created)
            }
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = "Kunde inte spara kortet. Dina ändringar finns kvar här."
        }
    }

    private func deleteCard() async {
        guard let card else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await service.deleteCard(id: card.id)
            onDeleted(card.id)
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = "Kunde inte radera kortet. Försök igen."
        }
    }

    private func emptyToNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func syncLinkDestination() {
        syncLinkDestination(on: &draft)
    }

    private func syncLinkDestination(on draft: inout ContentCardDraft) {
        switch linkDestinationType {
        case .external:
            draft.appDestination = nil
        case .courses:
            draft.linkUrl = ""
            draft.appDestination = "kurser"
        case .schedule:
            draft.linkUrl = ""
            draft.appDestination = "schema"
        case .specificCourse:
            draft.linkUrl = ""
            if let selectedEventId {
                draft.appDestination = "course:\(selectedEventId)"
            } else {
                draft.appDestination = nil
            }
        case .performances:
            draft.linkUrl = ""
            draft.appDestination = "forestallningar"
        case .specificPerformance:
            draft.linkUrl = ""
            if let selectedPerformanceSlug {
                draft.appDestination = "event:\(selectedPerformanceSlug)"
            } else {
                draft.appDestination = nil
            }
        }
    }

    private static func linkDestinationType(for destination: String?) -> ContentCardLinkDestinationType {
        guard let destination, !destination.isEmpty else { return .external }
        if destination == "kurser" { return .courses }
        if destination == "schema" { return .schedule }
        if destination == "forestallningar" { return .performances }
        if destination.hasPrefix("course:") { return .specificCourse }
        if destination.hasPrefix("event:") { return .specificPerformance }
        return .external
    }

    private static func selectedEventId(from destination: String?) -> Int? {
        guard let destination, destination.hasPrefix("course:") else { return nil }
        return Int(destination.replacingOccurrences(of: "course:", with: ""))
    }

    private static func selectedPerformanceSlug(from destination: String?) -> String? {
        guard let destination, destination.hasPrefix("event:") else { return nil }
        let slug = destination.replacingOccurrences(of: "event:", with: "")
        return slug.isEmpty ? nil : slug
    }

    private static func parseDate(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }

    private func formatPushSentTime(_ isoString: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: isoString) ?? {
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: isoString)
        }()
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private enum ContentCardLinkDestinationType: String, CaseIterable, Identifiable {
    case external
    case courses
    case schedule
    case specificCourse
    case performances
    case specificPerformance

    var id: Self { self }

    var label: String {
        switch self {
        case .external: "Extern länk"
        case .courses: "Kurser-fliken"
        case .schedule: "Schema-fliken"
        case .specificCourse: "En specifik kurs"
        case .performances: "Föreställningar-fliken"
        case .specificPerformance: "En specifik föreställning"
        }
    }
}

private struct PerformanceEventPicker: View {
    @EnvironmentObject private var rideau: RideauEventsService
    @Binding var selectedSlug: String?

    var body: some View {
        Picker("Föreställning", selection: $selectedSlug) {
            Text("Välj föreställning…").tag(Optional<String>.none)
            ForEach(rideau.events) { event in
                Text(event.title).tag(Optional(event.slug))
            }
        }
        .pickerStyle(.menu)
        .tint(.sdsAccent)
    }
}
