import AppKit
import Foundation
import Security

/// Installs an update in place of the running app: download the zip, verify
/// the signature, replace the bundle, then relaunch. Before this, "updating"
/// just opened the zip's URL in the browser, leaving the user to replace the
/// app by hand from the Downloads folder.
///
/// Replacing the app keeps the Accessibility permission and the Keychain key:
/// the new version carries the same signature, hence the same identity for TCC.
enum UpdateInstaller {
    enum Failure: LocalizedError {
        case download
        case archive
        case untrusted
        case translocated
        case notWritable(String)
        case replace

        var errorDescription: String? {
            switch self {
            case .download:
                loc("Téléchargement impossible. Vérifiez la connexion, puis réessayez.",
                    en: "Download failed. Check your connection, then try again.")
            case .archive:
                loc("L'archive téléchargée est illisible.",
                    en: "The downloaded archive cannot be read.")
            case .untrusted:
                loc("Cette mise à jour n'est pas signée par le développeur de Claudio : installation annulée.",
                    en: "This update is not signed by Claudio's developer: install cancelled.")
            case .translocated:
                loc("Claudio tourne depuis une copie temporaire. Glissez d'abord l'app dans le dossier Applications, relancez-la, puis réessayez.",
                    en: "Claudio is running from a temporary copy. Move the app to your Applications folder, launch it from there, then try again.")
            case .notWritable(let path):
                loc("Droits insuffisants pour remplacer l'app dans \(path).",
                    en: "Not enough permissions to replace the app in \(path).")
            case .replace:
                loc("Le remplacement a échoué. La version actuelle est intacte.",
                    en: "The replacement failed. The current version is untouched.")
            }
        }
    }

    /// Downloads the new version, extracts it, and verifies its signature.
    /// Returns the bundle ready to take the current app's place.
    static func prepare(from url: URL) async throws -> URL {
        let target = Bundle.main.bundleURL
        // An app launched from a zip runs read-only from a random mount
        // point: replacing it there would have no effect.
        guard !target.path.contains("/AppTranslocation/") else { throw Failure.translocated }
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw Failure.notWritable(parent.path)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (downloaded, response) = try? await URLSession.shared.download(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure.download
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudioUpdate-\(UUID().uuidString)")
        let unpacked = work.appendingPathComponent("app")
        let archive = work.appendingPathComponent("Claudio.zip")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            // The file handed back by `download` is deleted on return: move it first.
            try FileManager.default.moveItem(at: downloaded, to: archive)
        } catch {
            throw Failure.download
        }

        guard run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path]) == 0,
              let newApp = try? FileManager.default
                  .contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
                  .first(where: { $0.pathExtension == "app" }) else {
            try? FileManager.default.removeItem(at: work)
            throw Failure.archive
        }

        guard hasSameIdentityAsInstalledApp(newApp) else {
            try? FileManager.default.removeItem(at: work)
            throw Failure.untrusted
        }
        return newApp
    }

    /// Replaces the current app with `newApp`, then relaunches. The work is
    /// handed to a detached script: an app can't overwrite itself while it's
    /// running. On success, the app terminates and does not return.
    @MainActor
    static func installAndRelaunch(_ newApp: URL) throws {
        let work = newApp.deletingLastPathComponent().deletingLastPathComponent()
        let script = work.appendingPathComponent("install.sh")
        guard (try? replaceScript.write(to: script, atomically: true, encoding: .utf8)) != nil else {
            throw Failure.replace
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            newApp.path,
            Bundle.main.bundleURL.path,
            work.path
        ]
        do {
            try process.run()
        } catch {
            throw Failure.replace
        }
        NSApp.terminate(nil)
    }

    /// The script waits for Claudio to exit, swaps the bundles, then relaunches.
    /// The old app is only deleted once the copy succeeds: any failure
    /// restores the version that was in place.
    private static let replaceScript = """
    #!/bin/sh
    pid="$1"; new="$2"; target="$3"; work="$4"

    attempt=0
    while kill -0 "$pid" 2>/dev/null; do
        attempt=$((attempt + 1))
        [ "$attempt" -gt 100 ] && exit 1
        sleep 0.1
    done

    backup="$target.previous"
    rm -rf "$backup"
    mv "$target" "$backup" || exit 1
    if /usr/bin/ditto "$new" "$target"; then
        rm -rf "$backup"
    else
        rm -rf "$target"
        mv "$backup" "$target"
        exit 1
    fi

    /usr/bin/xattr -dr com.apple.quarantine "$target" 2>/dev/null
    /usr/bin/open "$target"
    rm -rf "$work"

    """

    /// The update must carry the identity of the installed app: a valid Apple
    /// signature, intact sealed resources, the same bundle id and the same
    /// development team. Otherwise we refuse to replace anything.
    private static func hasSameIdentityAsInstalledApp(_ candidate: URL) -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        var text = "anchor apple generic and identifier \"\(bundleID)\""
        if let team = teamIdentifier(of: Bundle.main.bundleURL) {
            text += " and certificate leaf[subject.OU] = \"\(team)\""
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(candidate as CFURL, [], &code) == errSecSuccess,
              let code else { return false }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private static func teamIdentifier(of appURL: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
