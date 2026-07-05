import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            OversiktView()
                .tabItem { Label("Översikt", systemImage: "square.grid.2x2") }

            AnmalningarView()
                .tabItem { Label("Anmälningar", systemImage: "list.clipboard") }

            KunderView()
                .tabItem { Label("Kunder", systemImage: "person.2") }

            WebSectionPlaceholderView(section: .shop)
                .tabItem { Label("Shop", systemImage: "bag") }

            MerView()
                .tabItem { Label("Mer", systemImage: "ellipsis.circle") }
        }
        .tint(.sdsDarkGreen)
        .fontDesign(.rounded)
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
                            .font(SDSType.rounded(30, weight: .bold))
                            .foregroundColor(.sdsDarkGreen)

                        Text(section.subtitle)
                            .font(SDSType.rounded(15))
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
                            .font(SDSType.rounded(12, weight: .bold))
                            .foregroundColor(.sdsMutedText)
                            .textCase(.uppercase)

                        ForEach(importedHints, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.sdsDarkGreen)
                                Text(item)
                                    .font(SDSType.rounded(14))
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    profileRow
                }

                Section("Sidor") {
                    NavigationLink {
                        WebSectionPlaceholderView(section: .calls)
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
                        WebSectionPlaceholderView(section: .schema)
                    } label: {
                        Label("Schema", systemImage: WebSection.schema.icon)
                    }

                    NavigationLink {
                        WebSectionPlaceholderView(section: .forms)
                    } label: {
                        Label("Formulär", systemImage: WebSection.forms.icon)
                    }
                }
            }
            .font(SDSType.rounded(15))
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
                            .font(SDSType.rounded(16, weight: .bold))
                            .foregroundColor(.sdsDarkGreen)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.fullName)
                        .font(SDSType.rounded(15, weight: .bold))
                        .foregroundColor(.sdsDarkGreen)
                    Text(profile.role.capitalized)
                        .font(SDSType.rounded(12))
                        .foregroundColor(.sdsMutedText)
                }
            }
        } else {
            Label("CORE", systemImage: "person.crop.circle")
                .foregroundColor(.sdsMutedText)
        }
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
                        .font(SDSType.rounded(15))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let passwordMessage {
                        Text(passwordMessage)
                            .font(SDSType.rounded(13))
                            .foregroundColor(passwordMessage.contains("sparat") ? .sdsDarkModeGreen : .sdsPink)
                    }
                } header: {
                    Text("API")
                } footer: {
                    Text("Används för kunddata och andra CogWork-endpoints som kräver lösenord.")
                }
            }
            .font(SDSType.rounded(15))
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
    MainTabView()
        .environmentObject(SupabaseAuthService())
        .environmentObject(CogWorkService())
}
