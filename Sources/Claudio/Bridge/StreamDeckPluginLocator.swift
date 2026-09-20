import Foundation

/// Whether the Stream Deck plugin is installed on this Mac. That is the
/// whole of Claudio's setup: the plugin sitting in the Stream Deck app's own
/// folder is what starts the bridge, with nothing to switch on.
///
/// A look at a path, never a launch and never a question to the Stream Deck
/// app: Claudio has no business talking to it, and the folder is there
/// whether the app is running or not.
struct StreamDeckPluginLocator {
    /// The plugin's bundle folder. An identifier, so it never changes: the
    /// Stream Deck app keys its plugins on it, and so does the installer.
    static let pluginFolderName = "com.okonoma.claudio.sdPlugin"

    /// Where the Stream Deck app keeps every plugin. Injectable so the tests
    /// read a temporary folder rather than this Mac's.
    var pluginsDirectory: URL

    init(pluginsDirectory: URL = StreamDeckPluginLocator.defaultPluginsDirectory) {
        self.pluginsDirectory = pluginsDirectory
    }

    static var defaultPluginsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.elgato.StreamDeck/Plugins")
    }

    /// True when the plugin's folder is there. A file of the same name is no
    /// plugin — a half-finished download, or something left behind — and the
    /// bridge has no reason to open a socket for it.
    var isInstalled: Bool {
        var isDirectory: ObjCBool = false
        let path = pluginsDirectory.appendingPathComponent(Self.pluginFolderName).path
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
