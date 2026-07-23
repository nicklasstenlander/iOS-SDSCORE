import SwiftUI

@main
struct SDSCoreApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var auth = SupabaseAuthService.shared
    @StateObject private var cogWork = CogWorkService()
    @StateObject private var goals = GoalsService()
    @StateObject private var push = PushNotificationService.shared

    init() {}

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(cogWork)
                .environmentObject(goals)
                .environmentObject(push)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: SupabaseAuthService
    @EnvironmentObject var cogWork: CogWorkService
    @EnvironmentObject var push: PushNotificationService

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
        .fullScreenCover(isPresented: Binding(
            get: { !push.hasSeenNotificationPrompt && !auth.isLoading },
            set: { _ in }
        )) {
            NotificationPrimingView()
                .environmentObject(push)
        }
        .task {
            syncDebugCogWorkPasswordIfNeeded()
        }
        .onChange(of: auth.isAuthenticated) { _, _ in
            syncDebugCogWorkPasswordIfNeeded()
            Task { await PushNotificationService.shared.reRegisterIfNeeded() }
        }
        .onChange(of: auth.profile) { _, profile in
            guard profile != nil else { return }
            Task { await PushNotificationService.shared.reRegisterIfNeeded() }
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
