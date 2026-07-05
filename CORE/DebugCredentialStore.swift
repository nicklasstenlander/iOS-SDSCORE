import Foundation

#if DEBUG
enum DebugCredentialStore {
    static let emailKey = "sds_core_debug_login_email"
    static let passwordKey = "sds_core_debug_login_password"
    static let cogWorkPasswordKey = "sds_core_debug_cogwork_password"

    static var email: String {
        get {
            migrateLegacyKeysIfNeeded()
            return UserDefaults.standard.string(forKey: emailKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: emailKey)
        }
    }

    static var password: String {
        get {
            migrateLegacyKeysIfNeeded()
            return UserDefaults.standard.string(forKey: passwordKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: passwordKey)
        }
    }

    static var cogWorkPassword: String {
        get { UserDefaults.standard.string(forKey: cogWorkPasswordKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: cogWorkPasswordKey) }
    }

    private static func migrateLegacyKeysIfNeeded() {
        let defaults = UserDefaults.standard

        if defaults.string(forKey: emailKey) == nil,
           let legacyEmail = defaults.string(forKey: "nicklas.stenlander@me.com"),
           !legacyEmail.isEmpty {
            defaults.set(legacyEmail, forKey: emailKey)
        }

        if defaults.string(forKey: passwordKey) == nil,
           let legacyPassword = defaults.string(forKey: "yxy8pyq1qre5PNT.pmb"),
           !legacyPassword.isEmpty {
            defaults.set(legacyPassword, forKey: passwordKey)
        }
    }
}
#endif
