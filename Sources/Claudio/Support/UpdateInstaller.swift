import AppKit
import Foundation
import Security

/// Installe une mise à jour à la place de l'app en cours : téléchargement du
/// zip, vérification de la signature, remplacement du bundle puis relance.
/// Avant cela la « mise à jour » se contentait d'ouvrir l'URL du zip dans le
/// navigateur, laissant l'utilisateur remplacer l'app à la main depuis le
/// dossier Téléchargements.
///
/// Remplacer l'app conserve la permission Accessibilité et la clé du Trousseau :
/// la nouvelle version porte la même signature, donc la même identité pour TCC.
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
                "Téléchargement impossible. Vérifiez la connexion, puis réessayez."
            case .archive:
                "L'archive téléchargée est illisible."
            case .untrusted:
                "Cette mise à jour n'est pas signée par le développeur de Claudio : installation annulée."
            case .translocated:
                "Claudio tourne depuis une copie temporaire. Glissez d'abord l'app dans le dossier Applications, relancez-la, puis réessayez."
            case .notWritable(let path):
                "Droits insuffisants pour remplacer l'app dans \(path)."
            case .replace:
                "Le remplacement a échoué. La version actuelle est intacte."
            }
        }
    }

    /// Télécharge la nouvelle version, l'extrait et vérifie sa signature.
    /// Renvoie le bundle prêt à prendre la place de l'app courante.
    static func prepare(from url: URL) async throws -> URL {
        let target = Bundle.main.bundleURL
        // Une app lancée depuis un zip tourne en lecture seule dans un point de
        // montage aléatoire : la remplacer là n'aurait aucun effet.
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
            // Le fichier rendu par `download` est effacé au retour : le déplacer d'abord.
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

    /// Remplace l'app courante par `newApp`, puis relance. Le travail est confié
    /// à un script détaché : une app ne peut pas s'écraser elle-même pendant
    /// qu'elle tourne. En cas de succès, l'app se termine et ne revient pas.
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

    /// Le script attend la fin de Claudio, échange les bundles et relance.
    /// L'ancienne app n'est effacée qu'une fois la copie réussie : le moindre
    /// échec restaure la version en place.
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

    /// La mise à jour doit porter l'identité de l'app installée : signature
    /// Apple valide, ressources scellées intactes, même bundle id et même
    /// équipe de développement. Sans quoi on refuse de remplacer quoi que ce soit.
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
