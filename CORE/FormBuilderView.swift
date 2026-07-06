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

                    Text("Välj vilka formulär som ska använda incheckning i svarslistan.")
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
                        FormCheckInToggleRow(
                            form: form,
                            isSaving: savingFormIDs.contains(form.id)
                        ) { enabled in
                            setCheckIn(enabled, for: form)
                        }
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
