import SwiftUI

struct AdminTabView: View {
    var body: some View {
        TabView {
            OversiktView()
                .tabItem { Label("Översikt", systemImage: "square.grid.2x2") }

            AnmalningarView()
                .tabItem { Label("Anmälningar", systemImage: "list.clipboard") }

            KunderView()
                .tabItem { Label("Kunder", systemImage: "person.2") }

            TodayScheduleView()
                .tabItem { Label("Schema", systemImage: "calendar") }

            MerView()
                .tabItem { Label("Mer", systemImage: "ellipsis.circle") }
        }
        .tint(.sdsDarkModeGreen)
    }
}

enum WebSection: CaseIterable, Identifiable {
    case customers
    case shop
    case calls
    case narvaro
    case signage
    case schema
    case forms

    var id: String { title }

    var title: String {
        switch self {
        case .customers: "Kunder"
        case .shop: "Shop"
        case .calls: "Samtal"
        case .narvaro: "Närvaro"
        case .signage: "Skyltning"
        case .schema: "Schema"
        case .forms: "Formulär"
        }
    }

    var icon: String {
        switch self {
        case .customers: "person.2"
        case .shop: "bag"
        case .calls: "phone"
        case .narvaro: "checkmark.square"
        case .signage: "tv"
        case .schema: "calendar"
        case .forms: "doc.text"
        }
    }

    var subtitle: String {
        switch self {
        case .customers:
            "Kontaktkort, deltagarhistorik och panelvy från PWA:n kräver användar-API innan den kan fyllas med data."
        case .shop:
            "Shopify-kopplingen finns i webbappen men är inte ansluten till Swift-servicen ännu."
        case .calls:
            "Telavox-samtal och agentdial är PWA-specifikt och behöver en native service innan funktionen kan aktiveras."
        case .narvaro:
            "Närvarolistorna kräver kurs- och deltagarunderlag utöver dagens bokningsmodell."
        case .signage:
            "Skyltningens spelarläge är en separat webbyta och behöver en native motsvarighet."
        case .schema:
            "Schema kräver events-endpointens fulla schemamodell innan den kan visas pixel-nära."
        case .forms:
            "Formulärflödet i PWA:n bygger på Supabase-tabeller som ännu inte är modellerade i appen."
        }
    }
}

struct WebSectionPlaceholderView: View {
    let section: WebSection

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: section.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.sdsDarkGreen)
                            .frame(width: 48, height: 48)
                            .background(Color.sdsLightGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text(section.title)
                            .font(SDSType.agrandir(30, weight: .bold))
                            .foregroundColor(.sdsDarkGreen)

                        Text(section.subtitle)
                            .font(SDSType.agrandir(15))
                            .foregroundColor(.sdsMutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color.sdsCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.sdsLightGreen.opacity(0.7), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Från sds-dashboard")
                            .font(SDSType.agrandir(12, weight: .bold))
                            .foregroundColor(.sdsMutedText)
                            .textCase(.uppercase)

                        ForEach(importedHints, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.sdsDarkGreen)
                                Text(item)
                                    .font(SDSType.agrandir(14))
                                    .foregroundColor(.sdsText)
                            }
                        }
                    }
                    .padding(18)
                    .background(Color.sdsCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(20)
            }
            .navigationTitle(section.title)
            .background(Color.sdsBackground.ignoresSafeArea())
        }
    }

    private var importedHints: [String] {
        [
            "Samma ikon och navigationsnamn som PWA:n.",
            "Samma kort-, text- och pillformspråk som övriga CORE-vyer.",
            "Redo att kopplas till native datakälla när motsvarande service finns."
        ]
    }
}

struct MerView: View {
    @EnvironmentObject var auth: SupabaseAuthService
    @EnvironmentObject var cogWork: CogWorkService
    @State private var isShowingCogWorkSettings = false
    @State private var callDirectoryStatus: String?
    @State private var isUpdatingCallDirectory = false
    @State private var dataRefreshStatus: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    profileRow
                }

                Section("Sidor") {
                    NavigationLink {
                        CourseCatalogView()
                    } label: {
                        Label("Kurskatalog", systemImage: "book.pages")
                    }

                    NavigationLink {
                        TodayScheduleView()
                    } label: {
                        Label("Schema", systemImage: WebSection.schema.icon)
                    }

                    NavigationLink {
                        SamtalView()
                    } label: {
                        Label("Samtal", systemImage: WebSection.calls.icon)
                    }

                    NavigationLink {
                        WebSectionPlaceholderView(section: .narvaro)
                    } label: {
                        Label("Närvaro", systemImage: WebSection.narvaro.icon)
                    }

                    NavigationLink {
                        WebSectionPlaceholderView(section: .signage)
                    } label: {
                        Label("Skyltning", systemImage: WebSection.signage.icon)
                    }

                    NavigationLink {
                        FormBuilderView()
                    } label: {
                        Label("Formulär", systemImage: WebSection.forms.icon)
                    }

                    NavigationLink {
                        CheckInView()
                    } label: {
                        Label("Incheckning", systemImage: "checkmark.circle")
                    }
                }

                Section {
                    Button {
                        Task { await refreshFromProxy() }
                    } label: {
                        HStack {
                            Label("Hämta senaste från proxy", systemImage: "arrow.clockwise")
                            Spacer()
                            if cogWork.isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(cogWork.isLoading)

                    Button(role: .destructive) {
                        Task { await purgeProxyAndRefresh() }
                    } label: {
                        Label("Rensa proxy och hämta från CogWork", systemImage: "trash.circle")
                    }
                    .disabled(cogWork.isLoading)

                    if let dataRefreshStatus {
                        Text(dataRefreshStatus)
                            .font(SDSType.agrandir(13))
                            .foregroundColor(dataRefreshStatus.contains("Kunde inte") ? .sdsPink : .sdsMutedText)
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Använd proxyhämtning normalt. Rensa proxy bara när du behöver tvinga fram helt färsk CogWork-data.")
                }

                Section {
                    Button {
                        auth.signOut()
                    } label: {
                        Label("Visa publik vy", systemImage: "eye")
                    }
                }

                Section {
                    Button {
                        Task { await updateCallDirectory() }
                    } label: {
                        HStack {
                            Label("Uppdatera nummerpresentation", systemImage: "phone.badge.checkmark")
                            Spacer()
                            if isUpdatingCallDirectory {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isUpdatingCallDirectory)

                    if let callDirectoryStatus {
                        Text(callDirectoryStatus)
                            .font(SDSType.agrandir(13))
                            .foregroundColor(callDirectoryStatus.contains("Kunde inte") ? .sdsPink : .sdsMutedText)
                    }
                } header: {
                    Text("Telefoni")
                } footer: {
                    Text("Aktivera efter första uppdateringen: Inställningar → Telefon → Blockering och identifiering av samtal → slå på CORE.")
                }
            }
            .font(SDSType.agrandir(15))
            .navigationTitle("Mer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isShowingCogWorkSettings = true
                        } label: {
                            Label("CogWork API", systemImage: "key")
                        }

                        Divider()

                        Button(role: .destructive) {
                            auth.signOut()
                        } label: {
                            Label("Logga ut", systemImage: "arrow.right.square")
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
            .scrollContentBackground(.hidden)
            .background(Color.sdsPageBackground)
        }
    }

    @ViewBuilder
    private var profileRow: some View {
        if let profile = auth.profile {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.sdsMidGreen)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(profile.firstName.prefix(1)))
                            .font(SDSType.agrandir(16, weight: .bold))
                            .foregroundColor(.sdsDarkGreen)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.fullName)
                        .font(SDSType.agrandir(15, weight: .bold))
                        .foregroundColor(.sdsDarkGreen)
                    Text(profile.role.capitalized)
                        .font(SDSType.agrandir(12))
                        .foregroundColor(.sdsMutedText)
                }
            }
        } else {
            Label("CORE", systemImage: "person.crop.circle")
                .foregroundColor(.sdsMutedText)
        }
    }

    private func updateCallDirectory() async {
        isUpdatingCallDirectory = true
        defer { isUpdatingCallDirectory = false }

        do {
            let count = try CORECallDirectoryStore.writeEntries(from: cogWork.bookings)
            try await CORECallDirectoryStore.reloadExtension()
            callDirectoryStatus = "Nummerpresentation uppdaterad med \(count) nummer."
        } catch {
            callDirectoryStatus = "Kunde inte uppdatera nummerpresentation: \(error.localizedDescription)"
        }
    }

    private func refreshFromProxy() async {
        await cogWork.loadAllData()
        dataRefreshStatus = cogWork.errorMessage ?? "Data hämtad från Cloudflare Proxy."
    }

    private func purgeProxyAndRefresh() async {
        await cogWork.forceRefreshFromCogWork()
        dataRefreshStatus = cogWork.errorMessage ?? "Proxy rensad och ny data hämtad från CogWork."
    }

}

struct CogWorkAPISettingsSheet: View {
    @EnvironmentObject var cogWork: CogWorkService
    @Environment(\.dismiss) private var dismiss
    @State private var cogWorkPassword = ""
    @State private var isVerifyingPassword = false
    @State private var passwordMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("CogWork-lösenord", text: $cogWorkPassword)
                        .font(SDSType.agrandir(15))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let passwordMessage {
                        Text(passwordMessage)
                            .font(SDSType.agrandir(13))
                            .foregroundColor(passwordMessage.contains("sparat") ? .sdsDarkModeGreen : .sdsPink)
                    }
                } header: {
                    Text("API")
                } footer: {
                    Text("Används för kunddata och andra CogWork-endpoints som kräver lösenord.")
                }
            }
            .font(SDSType.agrandir(15))
            .navigationTitle("CogWork API")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await verifyCogWorkPassword() }
                    } label: {
                        if isVerifyingPassword {
                            ProgressView()
                        } else {
                            Text("Spara")
                        }
                    }
                    .disabled(cogWorkPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifyingPassword)
                }
            }
            .onAppear {
                cogWorkPassword = cogWork.cogWorkPassword
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func verifyCogWorkPassword() async {
        isVerifyingPassword = true
        defer { isVerifyingPassword = false }

        let ok = await cogWork.verifyCogWorkPassword(cogWorkPassword)
        passwordMessage = ok ? "CogWork-lösenord sparat." : "Kunde inte verifiera lösenordet."
        if ok {
            dismiss()
        }
    }
}

#Preview {
    AdminTabView()
        .environmentObject(SupabaseAuthService())
        .environmentObject(CogWorkService())
        .environmentObject(GoalsService())
}
