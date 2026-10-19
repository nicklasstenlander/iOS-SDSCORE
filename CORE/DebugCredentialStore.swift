import Foundation

#if DEBUG
enum DebugCredentialStore {
    static let emailKey = "sds_core_debug_login_email"
    static let passwordKey = "sds_core_debug_login_password"

    static var email: String {
        get { UserDefaults.standard.string(forKey: emailKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: emailKey) }
    }

    static var password: String {
        get { UserDefaults.standard.string(forKey: passwordKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: passwordKey) }
    }
}
#endif
