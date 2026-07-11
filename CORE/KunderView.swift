import SwiftUI

struct KunderView: View {
    @EnvironmentObject var cogWork: CogWorkService
    @State private var query = ""
    @State private var selectedUser: CogWorkUser?
    @State private var isShowingCogWorkSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    searchField

                    if cogWork.cogWorkPassword.isEmpty {
                        MissingCogWorkPasswordCard {
                            isShowingCogWorkSettings = true
                        }
                    } else if let errorMessage = cogWork.errorMessage, cogWork.users.isEmpty {
                        EmptyStateCard(
                            icon: "exclamationmark.triangle",
                            title: "Kunde inte hämta kunder",
                            message: errorMessage,
                            tint: .sdsPink
                        )
                    } else if cogWork.isLoadingUsers {
                        LoadingCard(message: "Söker kunder...")
                    } else if cogWork.users.isEmpty {
                        EmptyStateCard(
                            icon: "person.text.rectangle",
                            title: "Sök efter kund",
                            message: "Skriv namn, e-post eller telefon för att hämta kunddata från CogWork."
                        )
                    } else {
                        resultsCard
                    }
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                await search()
            }
            .background(Color.sdsPageBackground.ignoresSafeArea())
            .navigationTitle("Kunder")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await search() }
                        } label: {
                            Label("Sök igen", systemImage: "arrow.clockwise")
                        }
                        .disabled(!canSearch)

                        Button {
                            isShowingCogWorkSettings = true
                        } label: {
                            Label("CogWork API", systemImage: "key")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .accessibilityLabel("Fler åtgärder")
                }
            }
            .sheet(isPresented: $isShowingCogWorkSettings) {
                CogWorkAPISettingsSheet()
                    .environmentObject(cogWork)
            }
            .sheet(item: $selectedUser) { user in
                CustomerDetailSheet(user: user)
                    .environmentObject(cogWork)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var header: some View {
        Text("Sök kontaktkort, deltagare och kundhistorik från CogWork.")
            .font(SDSType.agrandir(14))
            .foregroundColor(.sdsSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.sdsDarkModeGreen)

            TextField("Sök kund...", text: $query)
                .font(SDSType.agrandir(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    Task { await search() }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.sdsTertiaryText)
                }
                .accessibilityLabel("Rensa sökfält")

                Button {
                    Task { await search() }
                } label: {
                    Text("Sök")
                        .font(SDSType.agrandir(13, weight: .bold))
                        .foregroundColor(.sdsDarkModeGreen)
                }
                .disabled(!canSearch || cogWork.isLoadingUsers)
            }
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

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(cogWork.users.count) kunder")
                    .font(SDSType.agrandir(14, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)

                Spacer()

                Text("CogWork")
                    .font(SDSType.agrandir(12, weight: .bold))
                    .foregroundColor(.sdsDarkModeGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.sdsLightGreenSurface)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            ForEach(cogWork.users) { user in
                Button {
                    selectedUser = user
                } label: {
                    CustomerRow(user: user)
                }
                .buttonStyle(.plain)

                if user.id != cogWork.users.last?.id {
                    Rectangle()
                        .fill(Color.sdsBorder)
                        .frame(height: 1)
                        .padding(.leading, 66)
                }
            }
        }
        .background(Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var canSearch: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && !cogWork.cogWorkPassword.isEmpty
    }

    private func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else { return }
        await cogWork.searchUsers(query: trimmedQuery)
    }
}

private struct CustomerRow: View {
    let user: CogWorkUser

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.sdsMidGreen)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(initials)
                        .font(SDSType.agrandir(13, weight: .bold))
                        .foregroundColor(.sdsDarkGreen)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(user.displayName)
                        .font(SDSType.agrandir(15, weight: .bold))
                        .foregroundColor(.sdsPrimaryText)
                        .lineLimit(1)

                    if user.isMember == true {
                        SDSBadge(text: "Medlem", color: .sdsLightGreenSurface, textColor: .sdsDarkModeGreen)
                    }
                }

                Text(user.primaryContact)
                    .font(SDSType.agrandir(13))
                    .foregroundColor(.sdsSecondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.sdsTertiaryText)
        }
        .contentShape(Rectangle())
        .padding(16)
        .background(Color.sdsElevatedSurface)
    }

    private var initials: String {
        let parts = user.displayName.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        let value = (first + second).uppercased()
        return value.isEmpty ? "?" : value
    }
}

struct CustomerDetailSheet: View {
    let user: CogWorkUser
    @EnvironmentObject var cogWork: CogWorkService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    detailHeader
                    contactSection
                    coursesSection
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.sdsPageBackground.ignoresSafeArea())
            .navigationTitle("Kund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                        .font(SDSType.agrandir(15, weight: .bold))
                }
            }
            .task(id: user.id) {
                cogWork.selectedUserBookings = []
                await cogWork.loadBookings(forUserId: user.id)
            }
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("DELTAGARE")
                .font(SDSType.agrandir(12, weight: .bold))
                .foregroundColor(.sdsDarkModeGreen)

            Text(user.displayName)
                .font(SDSType.agrandir(26, weight: .bold))
                .foregroundColor(.sdsPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let membershipNumber = user.membershipNumber, !membershipNumber.isEmpty {
                SDSBadge(text: "Medlemsnr \(membershipNumber)", color: .sdsLightGreenSurface, textColor: .sdsDarkModeGreen)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var contactSection: some View {
        VStack(spacing: 16) {
            if let dateOfBirth = user.dateOfBirth {
                DetailLine(icon: "calendar", label: "Födelsedag", value: formatDate(dateOfBirth))
            }

            ForEach(Array((user.emails ?? []).enumerated()), id: \.offset) { _, email in
                DetailLine(
                    icon: "envelope",
                    label: "E-post",
                    value: email.email ?? "-",
                    actionTitle: "Maila",
                    actionURL: email.email.flatMap { URL(string: "mailto:\($0)") }
                )
            }

            ForEach(Array((user.telephoneNumbers ?? []).enumerated()), id: \.offset) { _, phone in
                DetailLine(
                    icon: "phone",
                    label: phone.type ?? "Telefon",
                    value: phone.telephoneNumber ?? "-",
                    actionTitle: "Ring",
                    actionURL: phone.callURL
                )
            }

            ForEach(Array((user.addresses ?? []).enumerated()), id: \.offset) { _, address in
                DetailLine(icon: "mappin.and.ellipse", label: "Adress", value: address.displayText)
            }
        }
        .padding(18)
        .background(Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var coursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .foregroundColor(.sdsDarkModeGreen)
                Text("KURSER")
                    .font(SDSType.agrandir(12, weight: .bold))
                    .foregroundColor(.sdsSecondaryText)
            }

            if cogWork.isLoading {
                ProgressView("Hämtar kurser...")
                    .font(SDSType.agrandir(14, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 84)
            } else if cogWork.selectedUserBookings.isEmpty {
                Text("Inga bokningar hämtade.")
                    .font(SDSType.agrandir(14))
                    .foregroundColor(.sdsSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.sdsSubtleSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(cogWork.selectedUserBookings) { booking in
                    CustomerCourseRow(booking: booking)
                }
            }
        }
        .padding(18)
        .background(Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func formatDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[2])/\(parts[1]) \(parts[0])"
    }
}

private struct DetailLine: View {
    let icon: String
    let label: String
    let value: String
    var actionTitle: String?
    var actionURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.sdsDarkModeGreen)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(SDSType.agrandir(12, weight: .bold))
                    .foregroundColor(.sdsSecondaryText)
                Text(value)
                    .font(SDSType.agrandir(14))
                    .foregroundColor(.sdsPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let actionTitle, let actionURL {
                Link(actionTitle, destination: actionURL)
                    .font(SDSType.agrandir(13, weight: .bold))
                    .foregroundColor(.sdsDarkModeGreen)
            }
        }
    }
}

private struct CustomerCourseRow: View {
    let booking: Booking

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(booking.event?.name ?? "Okänd kurs")
                    .font(SDSType.agrandir(15, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(BookingStatusFormatter.format(code: booking.status?.code, fallback: booking.status?.name))
                    .font(SDSType.agrandir(13))
                    .foregroundColor(.sdsSecondaryText)
            }

            Spacer(minLength: 8)

            if booking.payment?.paid == true {
                SDSBadge(text: "Betald", color: .sdsLightGreenSurface, textColor: .sdsDarkModeGreen)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sdsSubtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MissingCogWorkPasswordCard: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            EmptyStateCard(
                icon: "lock",
                title: "CogWork-lösenord krävs",
                message: "Kunddata kommer från CogWorks publika API. Lägg in lösenordet här eller via Mer > CogWork API."
            )

            Button(action: action) {
                Label("Öppna CogWork API", systemImage: "key")
                    .font(SDSType.agrandir(15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.sdsMidGreen)
                    .foregroundColor(.sdsDarkGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

private struct LoadingCard: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.sdsDarkModeGreen)
            Text(message)
                .font(SDSType.agrandir(15, weight: .bold))
                .foregroundColor(.sdsSecondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = .sdsDarkModeGreen

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 56, height: 56)
                .background(Color.sdsLightGreenSurface)
                .clipShape(Circle())

            Text(title)
                .font(SDSType.agrandir(17, weight: .bold))
                .foregroundColor(.sdsPrimaryText)

            Text(message)
                .font(SDSType.agrandir(14))
                .foregroundColor(.sdsSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.sdsElevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sdsBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private extension CogWorkUser {
    var displayName: String {
        name?.nilIfEmpty ?? [firstName, lastName]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " ")
            .nilIfEmpty ?? "Okänd kund"
    }

    var primaryContact: String {
        emails?.compactMap(\.email).first?.nilIfEmpty
            ?? telephoneNumbers?.compactMap(\.telephoneNumber).first?.nilIfEmpty
            ?? "Kontaktuppgift saknas"
    }
}

private extension UserTelephoneNumber {
    var callURL: URL? {
        guard let telephoneNumber else { return nil }
        let allowed = CharacterSet(charactersIn: "+0123456789")
        let cleaned = telephoneNumber.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "tel:\(cleaned)")
    }
}

private extension UserAddress {
    var displayText: String {
        [
            careOf,
            streetAddress,
            [postalCode, city].compactMap { $0 }.joined(separator: " "),
            country == "SE" ? nil : country
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: "\n")
    }
}

#Preview {
    KunderView()
        .environmentObject(CogWorkService())
}
