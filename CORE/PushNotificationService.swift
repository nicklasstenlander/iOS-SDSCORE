import Foundation
import Combine
import UIKit
import UserNotifications

struct NotificationPrefs: Codable {
    var notifyNews: Bool = true
    var notifyNewBookings: Bool = false
    var notifyPayments: Bool = false
    var followedEventIds: [Int] = []

    enum CodingKeys: String, CodingKey {
        case notifyNews = "notify_news"
        case notifyNewBookings = "notify_new_bookings"
        case notifyPayments = "notify_payments"
        case followedEventIds = "followed_event_ids"
    }
}

@MainActor
final class PushNotificationService: ObservableObject {
    static let shared = PushNotificationService()

    @Published var isRegistered = false
    @Published var permissionDenied = false
    @Published var prefs = NotificationPrefs()
    @Published var updateError: String?

    private let workerBaseURL = "https://sds-cogwork-proxy.nicklas-stenlander.workers.dev"
    private let tokenDefaultsKey = "sds_push_device_token"
    private let prefsDefaultsKey = "sds_push_notification_prefs"

    private var deviceToken: String? {
        get { UserDefaults.standard.string(forKey: tokenDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenDefaultsKey) }
    }

    private init() {
        loadPrefsFromDefaults()
        if deviceToken != nil { isRegistered = true }
        Task { await checkCurrentPermission() }
    }

    // MARK: - Tillstånd

    func requestPermissionAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            permissionDenied = !granted
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            permissionDenied = true
        }
    }

    func checkCurrentPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            permissionDenied = true
        case .authorized, .provisional, .ephemeral:
            permissionDenied = false
        default:
            break
        }
    }

    // MARK: - Registrering

    func registerDevice(token: String) async {
        deviceToken = token
        isRegistered = true
        permissionDenied = false
        await sendRegistration(token: token)
    }

    /// Kallas vid inloggning/utloggning för att synka userId+role med servern.
    func reRegisterIfNeeded() async {
        guard let token = deviceToken else { return }
        await sendRegistration(token: token)
    }

    private func sendRegistration(token: String) async {
        let auth = SupabaseAuthService.shared

        var payload: [String: Any] = [
            "deviceToken": token,
            "notifyNews": prefs.notifyNews,
            "notifyNewBookings": prefs.notifyNewBookings,
            "notifyPayments": prefs.notifyPayments,
            "followedEventIds": prefs.followedEventIds,
        ]
        if let userId = auth.profile?.id { payload["userId"] = userId }
        if let role = auth.profile?.role { payload["role"] = role }

        guard let url = URL(string: "\(workerBaseURL)/push/register-device"),
              let body = try? JSONSerialization.data(withJSONObject: payload)
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                updateError = "Kunde inte registrera enhet för notiser."
            }
        } catch {
            updateError = "Kunde inte registrera enhet för notiser."
        }
    }

    // MARK: - Preferenser

    func updatePreferences() async {
        savePrefsToDefaults()
        updateError = nil

        guard let token = deviceToken,
              let url = URL(string: "\(workerBaseURL)/push/preferences"),
              let body = try? JSONSerialization.data(withJSONObject: [
                  "deviceToken": token,
                  "notifyNews": prefs.notifyNews,
                  "notifyNewBookings": prefs.notifyNewBookings,
                  "notifyPayments": prefs.notifyPayments,
                  "followedEventIds": prefs.followedEventIds,
              ] as [String: Any])
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                updateError = "Kunde inte spara notisinställningar."
            }
        } catch {
            updateError = "Kunde inte spara notisinställningar."
        }
    }

    func toggleFollowedEvent(id: Int) async {
        if prefs.followedEventIds.contains(id) {
            prefs.followedEventIds.removeAll { $0 == id }
        } else {
            prefs.followedEventIds.append(id)
        }
        await updatePreferences()
    }

    func isFollowing(eventId: Int) -> Bool {
        prefs.followedEventIds.contains(eventId)
    }

    // MARK: - Persistens

    private func savePrefsToDefaults() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: prefsDefaultsKey)
        }
    }

    private func loadPrefsFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: prefsDefaultsKey),
              let decoded = try? JSONDecoder().decode(NotificationPrefs.self, from: data) else { return }
        prefs = decoded
    }

    private func prefsPayload() -> [String: Any] {
        [
            "notify_news": prefs.notifyNews,
            "notify_new_bookings": prefs.notifyNewBookings,
            "notify_payments": prefs.notifyPayments,
            "followed_event_ids": prefs.followedEventIds
        ]
    }
}
