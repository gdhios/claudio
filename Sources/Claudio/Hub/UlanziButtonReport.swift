import Foundation

/// What the Ulanzi posts to its button callback under AWTRIX NG:
/// `{"button":"left|middle|right","state":true|false,"uid":…}`, at the press
/// (`state:true`) and at the release. With a held notification on screen,
/// the two arrive within the same second, in either order: the hub acts on
/// the middle button going down alone, and reads nothing into the order.
enum UlanziButtonReport {
    static func isMiddlePress(_ body: Data) -> Bool {
        guard let report = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return false }
        return report["button"] as? String == "middle" && report["state"] as? Bool == true
    }
}
