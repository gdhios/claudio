import Foundation

/// The calls the Claude Code hub makes to the clock: a notification, its
/// dismissal, the indicator, and the address the device reports its
/// buttons to, or none. Same transport, same delays and same reading of the answers
/// as the face's calls.
extension UlanziClient {
    /// Shows `notification`, its keys set and no others.
    func notify(_ notification: UlanziNotification) async throws {
        let body = try Self.json(notification.fields)
        try await expectSuccess(send("POST", "api/v1/notifications", body: body, type: "application/json"))
    }

    /// Takes the held notification called `name` off the device. Already
    /// gone is no failure: the middle button dismisses the one on screen
    /// itself, before Claudio hears of the press.
    func dismiss(name: String) async throws {
        let answer = try await send("DELETE", "api/v1/notifications/\(name)")
        if answer.status == 404 { return }
        try expectSuccess(answer)
    }

    /// Lights indicator 1 as `indicator` says, or switches it off for nil.
    func setIndicator(_ indicator: UlanziIndicator?) async throws {
        let path = "api/v1/indicators/1"
        guard let indicator else {
            return try await expectSuccess(send("DELETE", path))
        }
        let body = try Self.json(["color": indicator.color, "blinkMs": indicator.blinkMs,
                                  "fadeMs": indicator.fadeMs])
        try await expectSuccess(send("PUT", path, body: body, type: "application/json"))
    }

    /// Where the device posts its button presses and releases from now on.
    func setButtonCallback(_ url: URL) async throws {
        try await setButtonCallback(address: url.absoluteString)
    }

    /// The device posts its buttons nowhere from now on: an empty address
    /// is the firmware's off.
    func clearButtonCallback() async throws {
        try await setButtonCallback(address: "")
    }

    private func setButtonCallback(address: String) async throws {
        let body = try Self.json(["buttonCallback": address])
        try await expectSuccess(send("PUT", "api/v1/system", body: body, type: "application/json"))
    }

    /// The call `command` names.
    func perform(_ command: UlanziCommand) async throws {
        switch command {
        case .notify(let notification): try await notify(notification)
        case .dismiss(let name): try await dismiss(name: name)
        case .indicator(let indicator): try await setIndicator(indicator)
        }
    }
}

private extension UlanziNotification {
    /// The keys set, under the firmware's names.
    var fields: [String: Any] {
        let fields: [String: Any?] = [
            "name": name, "text": text, "textColor": textColor, "durationMs": durationMs,
            "hold": hold, "wakeup": wakeup, "textBlinkMs": textBlinkMs, "soundRtttl": soundRtttl,
        ]
        return fields.compactMapValues { $0 }
    }
}
