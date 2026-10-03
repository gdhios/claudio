/// MediaRemote, the private framework behind the Now Playing controls of the
/// menu bar. Claudio reads it inside `osascript` (`JXAScript`) and sends it
/// commands from its own process (`MediaRemoteCommand`); both find it here.
enum MediaRemote {
    static let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework"

    /// The opening lines of every script that reads it: the Objective-C
    /// bridge, then the framework, loaded by its path.
    static let jxaPrelude = """
        ObjC.import('Foundation');
        $.NSBundle.bundleWithPath('\(frameworkPath)/').load;
        """
}
