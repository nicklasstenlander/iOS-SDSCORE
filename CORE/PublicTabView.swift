import SwiftUI

struct PublicTabView: View {
    @State private var selectedTab = PublicTab.home
    @State private var selectedCourseID: Int?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                onShowAllCourses: {
                    selectedTab = .courses
                },
                onOpenCourse: { event in
                    selectedCourseID = event.id
                    selectedTab = .courses
                }
            )
            .tabItem { Label("Hem", systemImage: "house") }
            .tag(PublicTab.home)

            NavigationStack {
                CourseCatalogView(mode: .public, initialSelectedEventID: selectedCourseID)
            }
            .tabItem { Label("Kurser", systemImage: "sparkles") }
            .tag(PublicTab.courses)

            AboutView()
                .tabItem { Label("Om oss", systemImage: "info.circle") }
                .tag(PublicTab.about)

            TodayScheduleView(mode: .public)
                .tabItem { Label("Schema", systemImage: "calendar") }
                .tag(PublicTab.schedule)

            PublicMerView()
                .tabItem { Label("Mer", systemImage: "ellipsis.circle") }
                .tag(PublicTab.more)
        }
        .tint(.sdsTeal)
    }
}

private enum PublicTab: Hashable {
    case home
    case courses
    case about
    case schedule
    case more
}

struct PublicMerView: View {
    @State private var showLogin = false
    @State private var safariURL: URL?
    private let mapsURL = URL(string: "maps://?q=Sollentuna%20Dans%20%26%20Scenskola&ll=59.4335,17.9321")!
    private let websiteURL = URL(string: "https://www.sollentunadansochscenskola.se")!

    var body: some View {
        NavigationStack {
            List {
                Section("Om skolan") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("Om Sollentuna Dans & Scenskola", systemImage: "info.circle")
                    }
                }

                Section("Kontakt") {
                    Link(destination: URL(string: "tel:0850278989")!) {
                        Label("Ring oss (08-502 78 989)", systemImage: "phone")
                    }
                    Link(destination: URL(string: "mailto:info@sollentunadansochscenskola.se")!) {
                        Label("Mejla oss", systemImage: "envelope")
                    }
                    Button { safariURL = URL(string: "https://instagram.com/sollentunadansochscenskola") } label: {
                        Label("Instagram", systemImage: "camera")
                    }
                    Button { safariURL = URL(string: "https://www.tiktok.com/@sollentunadansochscen") } label: {
                        Label("TikTok", systemImage: "music.note")
                    }
                    Button { safariURL = websiteURL } label: {
                        Label("Hemsida", systemImage: "safari")
                    }
                }

                Section("Hitta hit") {
                    Link(destination: mapsURL) {
                        Label("Kuskvägen 6, 191 62 Sollentuna", systemImage: "mappin")
                    }
                    Text("Mån–Fre 15:30–21:30\nLör 9:00–14:00\nSön 9:00–13:00")
                        .font(SDSType.agrandir(14))
                        .foregroundColor(.sdsSecondaryText)
                }

                Section {
                    Button {
                        showLogin = true
                    } label: {
                        Label("Logga in som administratör", systemImage: "lock.shield")
                    }
                }
            }
            .font(SDSType.agrandir(15))
            .navigationTitle("Mer")
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
            .sheet(isPresented: Binding(get: { safariURL != nil }, set: { if !$0 { safariURL = nil } })) {
                if let url = safariURL {
                    SafariView(url: url).ignoresSafeArea()
                }
            }
        }
    }
}

#Preview("PublicTabView") {
    PublicTabView()
        .environmentObject(CogWorkService())
        .environmentObject(SupabaseAuthService())
}

#Preview("PublicMerView") {
    PublicMerView()
        .environmentObject(CogWorkService())
        .environmentObject(SupabaseAuthService())
}
