import XCTest
@testable import Claudio

extension XCTestCase {
    /// The interface language for the rest of this test; the machine's own
    /// is put back once the test is over.
    func useLanguage(_ language: AppLanguage) {
        let previous = AppSettings.language
        AppSettings.language = language
        addTeardownBlock { AppSettings.language = previous }
    }
}
