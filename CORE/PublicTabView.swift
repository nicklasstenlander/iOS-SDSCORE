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

            TodayScheduleView(mode: .public)
                .tabItem { Label("Schema", systemImage: "calendar") }
                .tag(PublicTab.schedule)

            PublicMerView()
                .tabItem { Label("Mer", systemImage: "ellipsis.circle") }
                .tag(PublicTab.more)
        }
        .tint(.sdsDarkGreen)
    }
}

private enum PublicTab: Hashable {
    case home
    case courses
    case schedule
    case more
}

struct PublicMerView: View {
    @State private var showLogin = false

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
                    Link(destination: URL(string: "https://instagram.com/sollentunadansochscenskola")!) {
                        Label("Instagram", systemImage: "camera")
                    }
                }

                Section("Hitta hit") {
                    Label("Kuskvägen 6, 191 62 Sollentuna", systemImage: "mappin")
                    Text("Mån–Fre 15:30–21:30\nLör 9:00–14:00\nSön 9:00–13:00")
                        .font(.subheadline)
                        .foregroundColor(.gray)
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
        }
    }
}
