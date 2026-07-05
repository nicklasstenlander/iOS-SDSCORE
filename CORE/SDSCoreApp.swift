import SwiftUI

@main
struct SDSCoreApp: App {
    @StateObject private var auth = SupabaseAuthService()
    @StateObject private var cogWork = CogWorkService()
    @StateObject private var goals = GoalsService()

    init() {
        FontRegistrar.registerAgrandirFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(cogWork)
                .environmentObject(goals)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: SupabaseAuthService
    @EnvironmentObject var cogWork: CogWorkService

    var body: some View {
        Group {
            if auth.isLoading {
                ProgressView()
            } else if auth.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .task {
            syncDebugCogWorkPasswordIfNeeded()
        }
        .onChange(of: auth.isAuthenticated) { _, _ in
            syncDebugCogWorkPasswordIfNeeded()
        }
    }

    private func syncDebugCogWorkPasswordIfNeeded() {
        #if DEBUG
        guard auth.isAuthenticated,
              cogWork.cogWorkPassword.isEmpty,
              !DebugCredentialStore.cogWorkPassword.isEmpty else {
            return
        }

        cogWork.cogWorkPassword = DebugCredentialStore.cogWorkPassword
        #endif
    }
}
