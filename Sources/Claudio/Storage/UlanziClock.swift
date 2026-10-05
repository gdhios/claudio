import Foundation

/// One Ulanzi clock as Settings keeps it: a name to tell it from the
/// others, where it answers on the local network, and the two roles it can
/// take, ticked one by one: Claudio's face while he works, and the flags of
/// the Claude Code sessions.
struct UlanziClock: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var address: URL
    /// Claudio's face, through a `UlanziBridge` of its own.
    var face: Bool
    /// The Claude Code flags, through the hub.
    var alerts: Bool

    init(id: UUID = UUID(), name: String, address: URL, face: Bool = true, alerts: Bool = true) {
        self.id = id
        self.name = name
        self.address = address
        self.face = face
        self.alerts = alerts
    }

    /// The name of the first clock. A product's name, the same in every
    /// language, and a value kept with the clock, not a label.
    static let firstName = "Ulanzi"

    /// The name a new clock gets: "Ulanzi", then "Ulanzi 2", "Ulanzi 3"…,
    /// the first that none of `clocks` bears.
    static func defaultName(among clocks: [UlanziClock]) -> String {
        defaultName(notIn: Set(clocks.map(\.name)))
    }

    /// The same, against the names `taken`.
    static func defaultName(notIn taken: Set<String>) -> String {
        guard taken.contains(firstName) else { return firstName }
        var number = 2
        while taken.contains("\(firstName) \(number)") { number += 1 }
        return "\(firstName) \(number)"
    }
}
