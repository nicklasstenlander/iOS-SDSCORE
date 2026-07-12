import SwiftUI

struct ContentCardEditorView: View {
    let card: ContentCard?
    let onSaved: (ContentCard) -> Void
    let onDeleted: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = ContentCardsService()
    @State private var draft: ContentCardDraft
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
            _draft = State(initialValue: ContentCardDraft(
                type: card.type,
                title: card.title,
                body: card.body ?? "",
                imageUrl: card.imageUrl ?? "",
                linkUrl: card.linkUrl ?? "",
                linkLabel: card.linkLabel ?? "",
                startsAt: starts,
                expiresAt: expires,
                published: card.published,
                sortOrder: card.sortOrder
            ))
            _hasExpiry = State(initialValue: card.expiresAt != nil)
        } else {
            _draft = State(initialValue: ContentCardDraft())
            _hasExpiry = State(initialValue: false)
        }
    }

    var body: some View {
        List {
            errorSection
            settingsSection
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
            .tint(.sdsDarkModeGreen)
            .font(SDSType.agrandir(15))

            Toggle("Publicerad", isOn: $draft.published)
                .font(SDSType.agrandir(14, weight: .bold))
                .tint(.sdsDarkGreen)

            Stepper("Sorteringsordning: \(draft.sortOrder)", value: $draft.sortOrder, in: 0...999)
                .font(SDSType.agrandir(14))
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
                                .tint(.sdsDarkModeGreen)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }

            TextField("Länk-URL", text: $draft.linkUrl)
                .font(SDSType.agrandir(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

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
            .tint(.sdsDarkModeGreen)

            Toggle("Slutdatum", isOn: $hasExpiry)
                .font(SDSType.agrandir(14))
                .tint(.sdsDarkGreen)
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
                .tint(.sdsDarkModeGreen)
            }
        }
    }

    private var saveSection: some View {
        let titleEmpty = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView()
                            .tint(.sdsDarkGreen)
                    } else {
                        Text("Spara")
                            .font(SDSType.agrandir(17, weight: .bold))
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .disabled(isSaving || isDeleting || titleEmpty)
            .listRowBackground(titleEmpty ? Color.sdsSubtleSurface : Color.sdsMidGreen)
            .foregroundColor(.sdsDarkGreen)
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
                    startsAt: iso.string(from: draftToSave.startsAt),
                    expiresAt: draftToSave.expiresAt.map { iso.string(from: $0) },
                    published: draftToSave.published,
                    sortOrder: draftToSave.sortOrder
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

    private static func parseDate(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}
