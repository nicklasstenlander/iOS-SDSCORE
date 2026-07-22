import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @EnvironmentObject private var auth: SupabaseAuthService
    @EnvironmentObject private var cogWork: CogWorkService
    @EnvironmentObject private var push: PushNotificationService

    var body: some View {
        List {
            permissionSection

            if push.isRegistered {
                newsSection
                followedCoursesSection

                if auth.isAdmin {
                    adminSection
                } else if auth.isAuthenticated, let profile = auth.profile {
                    myClassesSection(profile: profile)
                }
            }

            if let error = push.updateError {
                Section {
                    Text(error)
                        .font(SDSType.agrandir(13))
                        .foregroundColor(.sdsPink)
                }
                .listRowBackground(Color.sdsPinkAdaptiveSurface)
            }
        }
        .font(SDSType.agrandir(15))
        .navigationTitle("Notiser")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.sdsPageBackground)
        .task {
            await push.checkCurrentPermission()
            if cogWork.events.isEmpty {
                await cogWork.loadEvents()
            }
        }
    }

    // MARK: - Sektioner

    @ViewBuilder
    private var permissionSection: some View {
        Section("Status") {
            if push.permissionDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Notiser blockerade", systemImage: "bell.slash.fill")
                        .font(SDSType.agrandir(14, weight: .bold))
                        .foregroundColor(.sdsPink)
                    Text("Ändra i Inställningar → Notiser → CORE")
                        .font(SDSType.agrandir(13))
                        .foregroundColor(.sdsSecondaryText)
                    Button("Öppna Inställningar") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(SDSType.agrandir(14, weight: .bold))
                    .foregroundColor(.sdsDarkModeGreen)
                }
                .padding(.vertical, 4)
            } else if push.isRegistered {
                Label("Notiser aktiverade", systemImage: "bell.badge.fill")
                    .font(SDSType.agrandir(14, weight: .bold))
                    .foregroundColor(.sdsDarkModeGreen)
            } else {
                Button {
                    Task { await push.requestPermissionAndRegister() }
                } label: {
                    Label("Aktivera notiser", systemImage: "bell.badge")
                        .font(SDSType.agrandir(14, weight: .bold))
                        .foregroundColor(.sdsDarkModeGreen)
                }
            }
        }
    }

    private var newsSection: some View {
        Section("Allmänt") {
            Toggle("Nyheter från skolan", isOn: $push.prefs.notifyNews)
                .font(SDSType.agrandir(14))
                .tint(.sdsDarkModeGreen)
                .onChange(of: push.prefs.notifyNews) { _, _ in
                    Task { await push.updatePreferences() }
                }
        }
    }

    @ViewBuilder
    private var followedCoursesSection: some View {
        let followed = cogWork.events.filter { push.prefs.followedEventIds.contains($0.id) }
        Section {
            if followed.isEmpty {
                Text("Du följer inga kurser ännu.\nTryck på klockan i en kurs för att aktivera notiser.")
                    .font(SDSType.agrandir(13))
                    .foregroundColor(.sdsSecondaryText)
                    .padding(.vertical, 4)
            } else {
                ForEach(followed) { event in
                    HStack {
                        Text(event.name ?? "–")
                            .font(SDSType.agrandir(14))
                            .foregroundColor(.sdsPrimaryText)
                        Spacer()
                        Button {
                            Task { await push.toggleFollowedEvent(id: event.id) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.sdsSecondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ta bort \(event.name ?? "kurs")")
                    }
                }
            }
        } header: {
            Text("Kurser du följer")
        } footer: {
            if !followed.isEmpty {
                Text("Du får notiser om uppdateringar för dessa kurser.")
            }
        }
    }

    private var adminSection: some View {
        Section("Admin") {
            Toggle("Nya anmälningar", isOn: $push.prefs.notifyNewBookings)
                .font(SDSType.agrandir(14))
                .tint(.sdsDarkModeGreen)
                .onChange(of: push.prefs.notifyNewBookings) { _, _ in
                    Task { await push.updatePreferences() }
                }
            Toggle("Betalningar", isOn: $push.prefs.notifyPayments)
                .font(SDSType.agrandir(14))
                .tint(.sdsDarkModeGreen)
                .onChange(of: push.prefs.notifyPayments) { _, _ in
                    Task { await push.updatePreferences() }
                }
        }
    }

    // Heuristisk matchning: instructorsName innehåller delar av profilens fullName.
    // OBS: inexakt tills ett dedikerat instructor_id-fält finns i API:t.
    @ViewBuilder
    private func myClassesSection(profile: UserProfile) -> some View {
        let myEvents = cogWork.events.filter { event in
            guard let instructorsName = event.instructorsName, !instructorsName.isEmpty else { return false }
            let nameParts = profile.fullName.split(separator: " ").map(String.init)
            return nameParts.contains { part in
                part.count > 1 && instructorsName.localizedCaseInsensitiveContains(part)
            }
        }

        if !myEvents.isEmpty {
            Section {
                ForEach(myEvents) { event in
                    let following = push.isFollowing(eventId: event.id)
                    Button {
                        Task { await push.toggleFollowedEvent(id: event.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.name ?? "–")
                                    .font(SDSType.agrandir(14, weight: .bold))
                                    .foregroundColor(.sdsPrimaryText)
                                if let time = event.schedule?.dayAndTimeInfo {
                                    Text(time)
                                        .font(SDSType.agrandir(12))
                                        .foregroundColor(.sdsSecondaryText)
                                }
                            }
                            Spacer()
                            Image(systemName: following ? "bell.fill" : "bell")
                                .foregroundColor(following ? .sdsDarkModeGreen : .sdsSecondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Mina klasser")
            } footer: {
                Text("Kurser matchade mot ditt namn som lärare. Matchningen är heuristisk.")
            }
        }
    }
}
