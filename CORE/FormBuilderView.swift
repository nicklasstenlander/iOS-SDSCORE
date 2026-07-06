import SwiftUI

struct FormBuilderView: View {
    @StateObject private var formsService = FormsService()
    @State private var forms: [FormSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var savingFormIDs: Set<String> = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Formulär")
                        .font(SDSType.rounded(28, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)

                    Text("Välj vilka formulär som ska använda incheckning och redigera deras fält och svarsalternativ.")
                        .font(SDSType.rounded(14))
                        .foregroundColor(.sdsSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(SDSType.rounded(13, weight: .bold))
                        .foregroundColor(.sdsPink)
                }
                .listRowBackground(Color.sdsPinkAdaptiveSurface)
            }

            Section("Inställningar") {
                if isLoading && forms.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.sdsDarkModeGreen)
                        Text("Laddar formulär...")
                            .font(SDSType.rounded(14, weight: .bold))
                            .foregroundColor(.sdsSecondaryText)
                    }
                    .padding(.vertical, 8)
                } else if forms.isEmpty {
                    Text("Inga formulär hittades")
                        .font(SDSType.rounded(14, weight: .bold))
                        .foregroundColor(.sdsSecondaryText)
                        .padding(.vertical, 8)
                } else {
                    ForEach(forms) { form in
                        VStack(alignment: .leading, spacing: 12) {
                            FormCheckInToggleRow(
                                form: form,
                                isSaving: savingFormIDs.contains(form.id)
                            ) { enabled in
                                setCheckIn(enabled, for: form)
                            }

                            NavigationLink {
                                FormBuilderEditorView(form: form) { updatedForm in
                                    updateForm(updatedForm)
                                }
                            } label: {
                                Label("Redigera fält och alternativ", systemImage: "slider.horizontal.3")
                                    .font(SDSType.rounded(14, weight: .bold))
                                    .foregroundColor(.sdsDarkModeGreen)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .font(SDSType.rounded(15))
        .navigationTitle("Formulär")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadForms() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(isLoading)
                .foregroundColor(.sdsDarkModeGreen)
                .accessibilityLabel("Uppdatera formulär")
            }
        }
        .task {
            await loadForms()
        }
        .refreshable {
            await loadForms()
        }
        .scrollContentBackground(.hidden)
        .background(Color.sdsPageBackground)
    }

    private func loadForms() async {
        isLoading = true
        defer { isLoading = false }

        do {
            forms = try await formsService.fetchForms()
            errorMessage = nil
        } catch {
            errorMessage = "Kunde inte hämta formulär."
        }
    }

    private func setCheckIn(_ enabled: Bool, for form: FormSummary) {
        guard let index = forms.firstIndex(where: { $0.id == form.id }) else { return }
        let previous = forms[index]
        forms[index].enableCheckin = enabled
        savingFormIDs.insert(form.id)

        Task {
            do {
                try await formsService.setFormCheckInEnabled(formId: form.id, enabled: enabled)
                savingFormIDs.remove(form.id)
                errorMessage = nil
            } catch {
                if let rollbackIndex = forms.firstIndex(where: { $0.id == form.id }) {
                    forms[rollbackIndex] = previous
                }
                savingFormIDs.remove(form.id)
                errorMessage = "Kunde inte spara inställningen för \(form.title)."
            }
        }
    }

    private func updateForm(_ form: FormSummary) {
        guard let index = forms.firstIndex(where: { $0.id == form.id }) else { return }
        forms[index] = form
    }
}

private struct FormBuilderEditorView: View {
    let form: FormSummary
    let onSaved: (FormSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var formsService = FormsService()
    @State private var enableCheckin: Bool
    @State private var fields: [FormFieldDraft] = []
    @State private var expandedFieldIDs: Set<UUID> = []
    @State private var fieldPendingDeletion: FormFieldDraft?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(form: FormSummary, onSaved: @escaping (FormSummary) -> Void) {
        self.form = form
        self.onSaved = onSaved
        _enableCheckin = State(initialValue: form.enableCheckin)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(form.title)
                        .font(SDSType.rounded(26, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)

                    Text(statusText(for: form.status))
                        .font(SDSType.rounded(12, weight: .bold))
                        .foregroundColor(.sdsSecondaryText)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(SDSType.rounded(13, weight: .bold))
                        .foregroundColor(.sdsPink)
                }
                .listRowBackground(Color.sdsPinkAdaptiveSurface)
            }

            Section("Inställningar") {
                Toggle("Aktivera incheckning för detta formulär", isOn: $enableCheckin)
                    .font(SDSType.rounded(14, weight: .bold))
                    .tint(.sdsDarkGreen)
                    .disabled(isSaving)
            }

            Section {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.sdsDarkModeGreen)
                        Text("Laddar fält...")
                            .font(SDSType.rounded(14, weight: .bold))
                            .foregroundColor(.sdsSecondaryText)
                    }
                    .padding(.vertical, 8)
                } else if fields.isEmpty {
                    Text("Inga fält ännu")
                        .font(SDSType.rounded(14, weight: .bold))
                        .foregroundColor(.sdsSecondaryText)
                        .padding(.vertical, 8)
                } else {
                    ForEach(fields) { field in
                        FormFieldEditorRow(
                            field: binding(for: field.localId),
                            isExpanded: Binding(
                                get: { expandedFieldIDs.contains(field.localId) },
                                set: { expanded in
                                    if expanded {
                                        expandedFieldIDs.insert(field.localId)
                                    } else {
                                        expandedFieldIDs.remove(field.localId)
                                    }
                                }
                            ),
                            canMoveUp: fields.first?.localId != field.localId,
                            canMoveDown: fields.last?.localId != field.localId,
                            moveUp: { moveField(field.localId, direction: -1) },
                            moveDown: { moveField(field.localId, direction: 1) },
                            requestDelete: { fieldPendingDeletion = field }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Fält")
                    Spacer()
                    Button {
                        addField()
                    } label: {
                        Label("Lägg till fält", systemImage: "plus")
                    }
                    .font(SDSType.rounded(12, weight: .bold))
                }
            }

            Section {
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
                                .font(SDSType.rounded(17, weight: .bold))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
                .disabled(isLoading || isSaving)
                .listRowBackground(Color.sdsMidGreen)
                .foregroundColor(.sdsDarkGreen)
            }
        }
        .font(SDSType.rounded(15))
        .navigationTitle("Bygg formulär")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadFields()
        }
        .confirmationDialog(
            "Ta bort fält?",
            isPresented: Binding(
                get: { fieldPendingDeletion != nil },
                set: { if !$0 { fieldPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Ta bort fält", role: .destructive) {
                if let fieldPendingDeletion {
                    deleteField(fieldPendingDeletion.localId)
                }
                fieldPendingDeletion = nil
            }
            Button("Avbryt", role: .cancel) {
                fieldPendingDeletion = nil
            }
        } message: {
            Text("Fältet tas bort permanent nästa gång du sparar formuläret.")
        }
        .scrollContentBackground(.hidden)
        .background(Color.sdsPageBackground)
    }

    private func loadFields() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let storedFields = try await formsService.fetchFormFields(formId: form.id)
            let storedOptions = try await formsService.fetchFormOptions(formId: form.id)
            fields = makeDrafts(fields: storedFields, options: storedOptions)
            expandedFieldIDs = Set(fields.map(\.localId))
            errorMessage = nil
        } catch {
            errorMessage = "Kunde inte ladda formulärets fält."
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await formsService.setFormCheckInEnabled(formId: form.id, enabled: enableCheckin)
            try await formsService.replaceFieldsAndOptions(formId: form.id, fields: normalizedFields())
            var updatedForm = form
            updatedForm.enableCheckin = enableCheckin
            onSaved(updatedForm)
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = "Kunde inte spara formuläret. Dina ändringar finns kvar här."
        }
    }

    private func makeDrafts(fields: [FormField], options: [FormOption]) -> [FormFieldDraft] {
        let optionsByField = Dictionary(grouping: options, by: \.fieldId)
        return fields.sorted { $0.sortOrder < $1.sortOrder }.enumerated().map { index, field in
            FormFieldDraft(
                key: field.key,
                type: field.type,
                label: field.label,
                helpText: field.helpText ?? "",
                required: field.required,
                sortOrder: index,
                options: (optionsByField[field.id] ?? [])
                    .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
                    .enumerated()
                    .map { optionIndex, option in
                        FormOptionDraft(
                            key: option.key,
                            label: option.label,
                            description: option.description ?? "",
                            dayTime: option.dayTime ?? "",
                            location: option.location ?? "",
                            level: option.level ?? "",
                            capacity: option.capacity.map(String.init) ?? "",
                            active: option.active,
                            sortOrder: optionIndex
                        )
                    }
            )
        }
    }

    private func binding(for localId: UUID) -> Binding<FormFieldDraft> {
        Binding(
            get: { fields.first { $0.localId == localId } ?? FormFieldDraft() },
            set: { updated in
                guard let index = fields.firstIndex(where: { $0.localId == localId }) else { return }
                fields[index] = updated
            }
        )
    }

    private func addField() {
        let field = FormFieldDraft(sortOrder: fields.count)
        fields.append(field)
        expandedFieldIDs.insert(field.localId)
    }

    private func deleteField(_ localId: UUID) {
        fields.removeAll { $0.localId == localId }
        expandedFieldIDs.remove(localId)
        normalizeSortOrder()
    }

    private func moveField(_ localId: UUID, direction: Int) {
        guard let index = fields.firstIndex(where: { $0.localId == localId }) else { return }
        let target = index + direction
        guard fields.indices.contains(target) else { return }
        fields.swapAt(index, target)
        normalizeSortOrder()
    }

    private func normalizedFields() -> [FormFieldDraft] {
        fields.enumerated().map { index, field in
            var copy = field
            copy.sortOrder = index
            copy.key = key(for: field.key, label: field.label, fallback: "field_\(index + 1)")
            copy.options = field.options.enumerated().map { optionIndex, option in
                var optionCopy = option
                optionCopy.sortOrder = optionIndex
                optionCopy.key = key(for: option.key, label: option.label, fallback: "option_\(optionIndex + 1)")
                return optionCopy
            }
            return copy
        }
    }

    private func normalizeSortOrder() {
        fields = normalizedFields()
    }

    private func key(for current: String, label: String, fallback: String) -> String {
        let source = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? label : current
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let characters = source.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        let key = characters.joined().split(separator: "_").joined(separator: "_")
        return key.isEmpty ? fallback : key
    }

    private func statusText(for status: String) -> String {
        switch status {
        case "published": "Publicerat"
        case "closed": "Stängt"
        case "draft": "Utkast"
        default: status.capitalized
        }
    }
}

private struct FormFieldEditorRow: View {
    @Binding var field: FormFieldDraft
    @Binding var isExpanded: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let requestDelete: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Label", text: $field.label)
                    .font(SDSType.rounded(15))

                Picker("Typ", selection: $field.type) {
                    ForEach(FormFieldType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .tint(.sdsDarkModeGreen)

                TextField("Hjälptext", text: $field.helpText)
                    .font(SDSType.rounded(15))

                Toggle("Obligatoriskt", isOn: $field.required)
                    .tint(.sdsDarkGreen)

                HStack(spacing: 12) {
                    Button(action: moveUp) {
                        Label("Upp", systemImage: "chevron.up")
                    }
                    .disabled(!canMoveUp)

                    Button(action: moveDown) {
                        Label("Ner", systemImage: "chevron.down")
                    }
                    .disabled(!canMoveDown)

                    Spacer()

                    Button(role: .destructive, action: requestDelete) {
                        Label("Ta bort fält", systemImage: "trash")
                    }
                }
                .font(SDSType.rounded(13, weight: .bold))

                if field.type.usesOptions {
                    Divider()
                    optionsEditor
                }
            }
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Namnlöst fält" : field.label)
                    .font(SDSType.rounded(16, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
                Text(field.type.title)
                    .font(SDSType.rounded(12, weight: .bold))
                    .foregroundColor(.sdsSecondaryText)
            }
        }
    }

    private var optionsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Alternativ")
                    .font(SDSType.rounded(14, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
                Spacer()
                Button {
                    addOption()
                } label: {
                    Label("Lägg till alternativ", systemImage: "plus")
                }
                .font(SDSType.rounded(12, weight: .bold))
                .foregroundColor(.sdsDarkModeGreen)
            }

            if field.options.isEmpty {
                Text("Inga alternativ ännu")
                    .font(SDSType.rounded(13, weight: .bold))
                    .foregroundColor(.sdsSecondaryText)
            } else {
                ForEach($field.options) { $option in
                    FormOptionEditorRow(option: $option, isCourseChoice: field.type == .courseChoice) {
                        field.options.removeAll { $0.localId == option.localId }
                        normalizeOptionSortOrder()
                    }
                }
            }
        }
    }

    private func addOption() {
        field.options.append(FormOptionDraft(sortOrder: field.options.count))
    }

    private func normalizeOptionSortOrder() {
        field.options = field.options.enumerated().map { index, option in
            var copy = option
            copy.sortOrder = index
            return copy
        }
    }
}

private struct FormOptionEditorRow: View {
    @Binding var option: FormOptionDraft
    let isCourseChoice: Bool
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Label", text: $option.label)
                .font(SDSType.rounded(15))

            TextField("Beskrivning", text: $option.description)
                .font(SDSType.rounded(15))

            Toggle("Aktiv", isOn: $option.active)
                .font(SDSType.rounded(14, weight: .bold))
                .tint(.sdsDarkGreen)

            if isCourseChoice {
                TextField("Dag/tid", text: $option.dayTime)
                    .font(SDSType.rounded(15))
                TextField("Plats", text: $option.location)
                    .font(SDSType.rounded(15))
                TextField("Nivå", text: $option.level)
                    .font(SDSType.rounded(15))
                TextField("Platsantal", text: $option.capacity)
                    .font(SDSType.rounded(15))
                    .keyboardType(.numberPad)
            }

            Button(role: .destructive, action: delete) {
                Label("Ta bort alternativ", systemImage: "trash")
            }
            .font(SDSType.rounded(13, weight: .bold))
        }
        .padding(12)
        .background(Color.sdsSubtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct FormCheckInToggleRow: View {
    let form: FormSummary
    let isSaving: Bool
    let setEnabled: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(form.title)
                        .font(SDSType.rounded(16, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)

                    Text(statusText)
                        .font(SDSType.rounded(12, weight: .bold))
                        .foregroundColor(.sdsSecondaryText)
                }

                Spacer()

                if isSaving {
                    ProgressView()
                        .tint(.sdsDarkModeGreen)
                }
            }

            Toggle("Aktivera incheckning för detta formulär", isOn: Binding(
                get: { form.enableCheckin },
                set: setEnabled
            ))
            .font(SDSType.rounded(14, weight: .bold))
            .tint(.sdsDarkGreen)
            .disabled(isSaving)
        }
        .padding(.vertical, 8)
    }

    private var statusText: String {
        switch form.status {
        case "published": "Publicerat"
        case "closed": "Stängt"
        case "draft": "Utkast"
        default: form.status.capitalized
        }
    }
}

#Preview {
    NavigationStack {
        FormBuilderView()
    }
}
