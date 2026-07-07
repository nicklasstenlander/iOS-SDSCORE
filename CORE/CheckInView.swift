import SwiftUI

struct CheckInView: View {
    @EnvironmentObject private var auth: SupabaseAuthService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var formsService = FormsService()

    @State private var forms: [FormSummary] = []
    @State private var selectedFormID: String?
    @State private var optionsByKey: [String: FormOption] = [:]
    @State private var searchText = ""
    @State private var filter = CheckInFilter.all
    @State private var isLoadingForms = true
    @State private var loadError: String?

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
    }

    private var selectedForm: FormSummary? {
        forms.first { $0.id == selectedFormID }
    }

    private var enableCheckIn: Bool {
        selectedForm?.enableCheckin == true
    }

    private var filteredSubmissions: [FormSubmission] {
        formsService.submissions.filter { submission in
            (!enableCheckIn || filter.matches(submission))
                && (searchText.isEmpty || searchableText(for: submission).localizedCaseInsensitiveContains(searchText))
        }
    }

    private var checkedInCount: Int {
        formsService.submissions.filter(\.isCheckedIn).count
    }

    var body: some View {
        NavigationStack {
            Group {
                if isWideLayout {
                    ScrollView {
                        mainContent
                            .padding(20)
                            .frame(maxWidth: 1240)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    List {
                        compactContent
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.sdsPageBackground.ignoresSafeArea())
            .navigationTitle("Öppet hus")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshSelectedForm() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .disabled(selectedFormID == nil)
                    .foregroundColor(.sdsDarkModeGreen)
                    .accessibilityLabel("Uppdatera svar")
                }
            }
            .task {
                await loadFormsIfNeeded()
            }
            .task(id: selectedFormID) {
                await loadSelectedFormData()
            }
            .onDisappear {
                formsService.stopPolling()
            }
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            controls
            statusMessage

            if filteredSubmissions.isEmpty && !formsService.isLoading {
                emptyState
            } else {
                LazyVGrid(columns: wideColumns, spacing: 12) {
                    ForEach(filteredSubmissions) { submission in
                        CheckInSubmissionRow(
                            submission: submission,
                            name: displayName(for: submission),
                            contact: contactText(for: submission),
                            courseLabels: courseLabels(for: submission),
                            answerSummary: answerSummary(for: submission),
                            isWide: true,
                            showCheckInControls: enableCheckIn
                        ) {
                            toggle(submission)
                        }
                    }
                }
            }
        }
    }

    private var compactContent: some View {
        Group {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                controls
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                statusMessage
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if filteredSubmissions.isEmpty && !formsService.isLoading {
                emptyState
                    .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredSubmissions) { submission in
                    CheckInSubmissionRow(
                        submission: submission,
                        name: displayName(for: submission),
                        contact: contactText(for: submission),
                        courseLabels: courseLabels(for: submission),
                        answerSummary: answerSummary(for: submission),
                        isWide: false,
                        showCheckInControls: enableCheckIn
                    ) {
                        toggle(submission)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ÖPPET HUS")
                .font(SDSType.agrandir(12, weight: .bold))
                .foregroundColor(.sdsDarkModeGreen)

            Text(enableCheckIn ? "Svar med incheckning" : "Formulärsvar")
                .font(SDSType.agrandir(isWideLayout ? 38 : 30, weight: .bold))
                .foregroundColor(.sdsPrimaryText)

            Text(enableCheckIn ? "\(checkedInCount) incheckade av \(formsService.submissions.count) svar" : "\(formsService.submissions.count) svar")
                .font(SDSType.agrandir(15))
                .foregroundColor(.sdsSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if forms.count > 1 {
                Picker("Formulär", selection: Binding(
                    get: { selectedFormID ?? "" },
                    set: { selectedFormID = $0 }
                )) {
                    ForEach(forms) { form in
                        Text(form.title).tag(form.id)
                    }
                }
                .pickerStyle(.menu)
                .font(SDSType.agrandir(15, weight: .bold))
                .tint(.sdsDarkModeGreen)
            }

            searchField

            if enableCheckIn {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(CheckInFilter.allCases) { item in
                            SDSPill(title: item.title, isSelected: filter == item) {
                                filter = item
                            }
                        }
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.sdsDarkModeGreen)
            TextField("Sök namn, e-post eller telefon...", text: $searchText)
                .font(SDSType.agrandir(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.sdsTertiaryText)
                }
                .accessibilityLabel("Rensa sökning")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color.sdsSubtleSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var statusMessage: some View {
        if isLoadingForms || formsService.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.sdsDarkModeGreen)
                Text("Laddar formulärsvar...")
                    .font(SDSType.agrandir(14, weight: .bold))
                    .foregroundColor(.sdsSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let error = loadError ?? formsService.errorMessage {
            Text(error)
                .font(SDSType.agrandir(13, weight: .bold))
                .foregroundColor(.sdsPink)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sdsPinkAdaptiveSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.sdsDarkModeGreen)
            Text(forms.isEmpty ? "Inga publicerade formulär hittades" : "Inga svar matchar urvalet")
                .font(SDSType.agrandir(15, weight: .bold))
                .foregroundColor(.sdsSecondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color.sdsElevatedSurface)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sdsBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var wideColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private func loadFormsIfNeeded() async {
        guard forms.isEmpty else { return }
        isLoadingForms = true
        defer { isLoadingForms = false }

        do {
            forms = try await formsService.fetchPublishedForms()
            selectedFormID = forms.first?.id
            loadError = nil
        } catch {
            loadError = "Kunde inte hämta publicerade formulär."
        }
    }

    private func loadSelectedFormData() async {
        guard let selectedFormID else { return }
        formsService.stopPolling()
        formsService.isLoading = true
        defer { formsService.isLoading = false }

        do {
            let options = try await formsService.fetchOptions(formId: selectedFormID)
            optionsByKey = Dictionary(uniqueKeysWithValues: options.map { ($0.key, $0) })
            formsService.submissions = try await formsService.fetchSubmissions(formId: selectedFormID)
            formsService.startPolling(formId: selectedFormID, interval: 4)
            loadError = nil
        } catch {
            loadError = "Kunde inte ladda formulärsvaren."
        }
    }

    private func refreshSelectedForm() async {
        guard let selectedFormID else { return }
        await formsService.refreshSubmissions(formId: selectedFormID)
    }

    private func toggle(_ submission: FormSubmission) {
        guard enableCheckIn else { return }

        let by = auth.profile?.fullName ?? "CORE"
        Task {
            await formsService.updateCheckInOptimistically(
                submissionId: submission.id,
                checkedIn: !submission.isCheckedIn,
                by: by
            )
        }
    }

    private func displayName(for submission: FormSubmission) -> String {
        if let name = nonEmpty(submission.respondentName) {
            return name
        }

        let nameKeys = submission.answers.keys.sorted().filter { key in
            let normalized = key.lowercased()
            return normalized.contains("namn") || normalized.contains("name")
        }

        for key in nameKeys {
            if let value = nonEmpty(submission.answers[key]?.displayString) {
                return value
            }
        }

        return "Namn saknas"
    }

    private func contactText(for submission: FormSubmission) -> String {
        var values: [String] = []
        if let email = nonEmpty(submission.respondentEmail) ?? answerValue(in: submission, matching: ["email", "e-post", "mail"]) {
            values.append(email)
        }
        if let phone = nonEmpty(submission.respondentPhone) ?? answerValue(in: submission, matching: ["telefon", "phone", "mobil"]) {
            values.append(phone)
        }
        return values.isEmpty ? "Kontakt saknas" : values.joined(separator: " · ")
    }

    private func courseLabels(for submission: FormSubmission) -> [String] {
        submission.selectedOptionKeys.compactMap { optionsByKey[$0]?.label }
    }

    private func answerSummary(for submission: FormSubmission) -> String {
        let values = submission.answers
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { $0.value.displayString }
            .compactMap(nonEmpty)

        guard !values.isEmpty else { return "Svar saknas" }
        return values.joined(separator: " · ")
    }

    private func searchableText(for submission: FormSubmission) -> String {
        ([
            displayName(for: submission),
            contactText(for: submission),
            answerSummary(for: submission)
        ] + courseLabels(for: submission)).joined(separator: " ")
    }

    private func answerValue(in submission: FormSubmission, matching fragments: [String]) -> String? {
        for key in submission.answers.keys.sorted() {
            let normalized = key.lowercased()
            if fragments.contains(where: { normalized.contains($0) }),
               let value = nonEmpty(submission.answers[key]?.displayString) {
                return value
            }
        }
        return nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty || trimmed == "–" ? nil : trimmed
    }
}

private struct CheckInSubmissionRow: View {
    let submission: FormSubmission
    let name: String
    let contact: String
    let courseLabels: [String]
    let answerSummary: String
    let isWide: Bool
    let showCheckInControls: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(SDSType.agrandir(isWide ? 20 : 17, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)
                        .lineLimit(2)

                    if showCheckInControls && submission.isCheckedIn {
                        SDSBadge(text: "Incheckad", color: .sdsMidGreen, textColor: .sdsDarkGreen)
                    }
                }

                Text(contact)
                    .font(SDSType.agrandir(14))
                    .foregroundColor(.sdsSecondaryText)
                    .lineLimit(2)

                if !courseLabels.isEmpty {
                    Text(courseLabels.joined(separator: " · "))
                        .font(SDSType.agrandir(14, weight: .bold))
                        .foregroundColor(.sdsDarkModeGreen)
                        .lineLimit(isWide ? 3 : 2)
                }

                Text(answerSummary)
                    .font(SDSType.agrandir(12))
                    .foregroundColor(.sdsTertiaryText)
                    .lineLimit(isWide ? 3 : 2)
            }

            if showCheckInControls {
                Spacer(minLength: 8)

                Button(action: toggle) {
                    Image(systemName: submission.isCheckedIn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: isWide ? 42 : 34, weight: .semibold))
                        .foregroundColor(submission.isCheckedIn ? .sdsDarkGreen : .sdsTertiaryText)
                        .frame(width: isWide ? 64 : 54, height: isWide ? 64 : 54)
                        .background(submission.isCheckedIn ? Color.sdsMidGreen : Color.sdsSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(submission.isCheckedIn ? "Ångra incheckning" : "Checka in")
            }
        }
        .padding(isWide ? 18 : 14)
        .frame(maxWidth: .infinity, minHeight: isWide ? 150 : 118, alignment: .leading)
        .background(showCheckInControls && submission.isCheckedIn ? Color.sdsLightGreenSurface : Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(showCheckInControls && submission.isCheckedIn ? Color.sdsMidGreen : Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private enum CheckInFilter: CaseIterable, Identifiable {
    case all
    case checkedIn
    case notCheckedIn

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Alla"
        case .checkedIn: "Incheckade"
        case .notCheckedIn: "Ej incheckade"
        }
    }

    func matches(_ submission: FormSubmission) -> Bool {
        switch self {
        case .all: true
        case .checkedIn: submission.isCheckedIn
        case .notCheckedIn: !submission.isCheckedIn
        }
    }
}

#Preview {
    CheckInView()
        .environmentObject(SupabaseAuthService.shared)
}
