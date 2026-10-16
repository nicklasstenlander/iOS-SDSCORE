import SwiftUI

@main
struct SDSCoreApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var auth = SupabaseAuthService.shared
    @StateObject private var cogWork = CogWorkService()
    @StateObject private var goals = GoalsService()
    @StateObject private var push = PushNotificationService.shared
    @StateObject private var rideau = RideauEventsService()

    init() {}

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(cogWork)
                .environmentObject(goals)
                .environmentObject(push)
                .environmentObject(rideau)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: SupabaseAuthService
    @EnvironmentObject var cogWork: CogWorkService
    @EnvironmentObject var push: PushNotificationService
    @EnvironmentObject var rideau: RideauEventsService
    @Environment(\.scenePhase) private var scenePhase

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
            // Icke-blockerande förhämtning av appdata parallellt med auth
            Task { await cogWork.loadAllDataIfNeeded() }
            Task { await rideau.loadIfNeeded() }
        }
        .onChange(of: auth.isAuthenticated) { _, _ in
            syncDebugCogWorkPasswordIfNeeded()
            Task { await PushNotificationService.shared.reRegisterIfNeeded() }
        }
        .onChange(of: auth.profile) { _, profile in
            guard profile != nil else { return }
            Task { await PushNotificationService.shared.reRegisterIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await rideau.loadIfNeeded() }
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
