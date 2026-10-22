import Foundation

extension UserDefaults {
    /// A cleared suite, so tests never read or write the real app preferences
    static func makeTestSuite() -> UserDefaults {
        let name = "com.thelazydeveloper.dorso.tests"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("Could not create the test defaults suite")
        }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
