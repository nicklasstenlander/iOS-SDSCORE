import SwiftUI

@main
struct SDSCoreApp: App {
    @StateObject private var auth = SupabaseAuthService.shared
    @StateObject private var cogWork = CogWorkService()
    @StateObject private var goals = GoalsService()

    init() {}

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
                LaunchScreenView()
            } else if auth.isAuthenticated {
                AdminTabView()
            } else {
                PublicTabView()
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
