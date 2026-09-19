import XCTest
@testable import Claudio

/// Whether the Stream Deck plugin sits where the Stream Deck app keeps its
/// plugins. That answer is what switches the bridge on by itself, so it is
/// read from a temporary folder here rather than from this Mac's.
final class StreamDeckPluginLocatorTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudioTests.plugins.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    private var locator: StreamDeckPluginLocator {
        StreamDeckPluginLocator(pluginsDirectory: directory)
    }

    func testNoPluginFolderMeansNotInstalled() {
        XCTAssertFalse(locator.isInstalled)
    }

    /// A plugin is a folder bearing the plugin's own identifier: that name is
    /// a contract with the Stream Deck app and is never renamed.
    func testThePluginFolderIsWhatCounts() throws {
        XCTAssertEqual(StreamDeckPluginLocator.pluginFolderName, "com.okonoma.claudio.sdPlugin")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(StreamDeckPluginLocator.pluginFolderName),
            withIntermediateDirectories: false)
        XCTAssertTrue(locator.isInstalled)
    }

    /// A file of that name is no plugin: half a download, or something left
    /// behind. The bridge shouldn't start for it.
    func testAPlainFileOfTheSameNameIsNoPlugin() throws {
        try Data().write(
            to: directory.appendingPathComponent(StreamDeckPluginLocator.pluginFolderName))
        XCTAssertFalse(locator.isInstalled)
    }

    /// A missing plugins folder is the ordinary case on a Mac with no Stream
    /// Deck app at all: an answer, not a failure.
    func testAMissingPluginsFolderIsNotInstalled() throws {
        try FileManager.default.removeItem(at: directory)
        XCTAssertFalse(locator.isInstalled)
    }

    /// Where the Stream Deck app keeps its plugins. Read-only: nothing is
    /// created on this Mac, only the path is checked.
    func testItLooksWhereTheStreamDeckAppKeepsItsPlugins() {
        XCTAssertTrue(
            StreamDeckPluginLocator().pluginsDirectory.path
                .hasSuffix("/Library/Application Support/com.elgato.StreamDeck/Plugins"),
            StreamDeckPluginLocator().pluginsDirectory.path)
    }
}
