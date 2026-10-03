import Foundation

extension Bundle {
    /// The version the bundle carries; "dev" from `swift run`, which has no
    /// bundle to carry one.
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
