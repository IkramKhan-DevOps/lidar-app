import Foundation

enum TokenDefaults {
    // Must match your Flutter SharedPreferences key
    static let key = "auth_token"

    // Try standard UserDefaults first, then the Flutter suite
    static func read(key: String = key) -> String? {
        if let value = UserDefaults.standard.string(forKey: key) {
            return value
        }
        if let value = UserDefaults(suiteName: "flutter")?.string(forKey: key) {
            return value
        }
        return nil
    }
}