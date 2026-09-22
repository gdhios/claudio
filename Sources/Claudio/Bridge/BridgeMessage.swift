import Foundation

/// The channel between Claudio and its Stream Deck plugin, as values. The
/// transport is elsewhere: these frames are parsed and built without a socket
/// in sight, which is how the contract can be tested against the fixtures the
/// plugin reads too.
enum BridgeProtocol {
    /// Bumped only when a frame changes shape. The handshake carries it, and
    /// a plugin that speaks another one is turned away rather than tolerated.
    static let version = 1
}

// MARK: - Plugin → app

/// What a key press asks for. Keyed on `type`, decoded by hand: an unknown
/// frame throws rather than turning into a default, because a plugin from
/// another version guessing wrong is worse than one that is refused.
enum BridgeInbound: Equatable, Decodable {
    case hello(version: Int, token: String, plugin: String)
    case action(BridgeActionID)
    case dictationDown(language: BridgeDictationLanguage, output: DictationOutput)
    case dictationUp
    case dictationCancel
    case window(BridgeWindowCommand)
    case openSettings

    private enum Key: String, CodingKey {
        case type, v, token, plugin, id, event, language, output, layout, target
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        switch try container.decode(String.self, forKey: .type) {
        case "hello":
            self = .hello(version: try container.decode(Int.self, forKey: .v),
                          token: try container.decode(String.self, forKey: .token),
                          plugin: try container.decode(String.self, forKey: .plugin))

        case "action":
            let id = try container.decode(String.self, forKey: .id)
            guard let action = BridgeActionID(wireName: id) else {
                throw Self.unknown(id, forKey: .id, in: container)
            }
            self = .action(action)

        case "dictation":
            let event = try container.decode(String.self, forKey: .event)
            switch event {
            case "down":
                // Both belong to the key that was pressed, as they belong to
                // a shortcut: a `down` without them is refused, never given
                // a default the speaker didn't choose.
                let output = try container.decode(String.self, forKey: .output)
                guard let output = DictationOutput(rawValue: output) else {
                    throw Self.unknown(output, forKey: .output, in: container)
                }
                self = .dictationDown(
                    language: try container.decode(BridgeDictationLanguage.self, forKey: .language),
                    output: output)
            case "up": self = .dictationUp
            case "cancel": self = .dictationCancel
            default: throw Self.unknown(event, forKey: .event, in: container)
            }

        case "window":
            let layout = try container.decode(String.self, forKey: .layout)
            guard let command = BridgeWindowCommand(wireName: layout) else {
                throw Self.unknown(layout, forKey: .layout, in: container)
            }
            self = .window(command)

        case "open":
            let target = try container.decode(String.self, forKey: .target)
            guard target == "settings" else {
                throw Self.unknown(target, forKey: .target, in: container)
            }
            self = .openSettings

        case let type:
            throw Self.unknown(type, forKey: .type, in: container)
        }
    }

    private static func unknown(_ value: String, forKey key: Key,
                                in container: KeyedDecodingContainer<Key>) -> DecodingError {
        DecodingError.dataCorruptedError(
            forKey: key, in: container,
            debugDescription: "unknown \(key.stringValue) “\(value)”")
    }
}

/// What a key launches: a catalog entry, the custom action, or the palette.
enum BridgeActionID: Equatable {
    case catalog(ClaudioAction)
    case free
    case palette

    /// The name on the wire is the action's own rawValue, so a key and a
    /// shortcut name the same thing.
    init?(wireName: String) {
        switch wireName {
        case "free": self = .free
        case "palette": self = .palette
        default:
            guard let action = ClaudioAction(rawValue: wireName) else { return nil }
            self = .catalog(action)
        }
    }
}

/// Which of the two dictation shortcuts the key stands for. The languages
/// themselves live in the settings: the plugin names the slot, not a locale,
/// so changing the language in Claudio changes what the key dictates.
enum BridgeDictationLanguage: String, Codable {
    case primary, secondary
}

/// What a window key does: snap to a layout, or move to the next display.
/// The next display is no layout — it moves the window without reshaping it —
/// but it shares the field because it shares the key.
enum BridgeWindowCommand: Equatable {
    case layout(WindowLayout)
    case nextScreen

    init?(wireName: String) {
        if wireName == "nextScreen" {
            self = .nextScreen
            return
        }
        guard let layout = WindowLayout(rawValue: wireName) else { return nil }
        self = .layout(layout)
    }
}

// MARK: - App → plugin

/// What the app tells the keys. The state goes out whole on every change:
/// a plugin that misses a frame is still right at the next one.
enum BridgeOutbound: Equatable, Encodable {
    case welcome(version: Int, app: String, state: BridgeState)
    case state(BridgeState)
    /// The microphone's loudness, 0…1, while a dictation listens.
    case level(Float)
    case bye
    case error(code: BridgeErrorCode, message: String)

    private enum Key: String, CodingKey {
        case type, v, app, state, value, code, message
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .welcome(let version, let app, let state):
            try container.encode("welcome", forKey: .type)
            try container.encode(version, forKey: .v)
            try container.encode(app, forKey: .app)
            try container.encode(state, forKey: .state)
        case .state(let state):
            try container.encode("state", forKey: .type)
            // Flat, unlike the welcome's: the state's own fields sit next to
            // `type` rather than under a key of their own. The state asks the
            // same encoder for a keyed container of its own while this one is
            // still alive, which JSONEncoder answers with the same storage at
            // the same coding path — so the two sets of keys land in one object.
            try state.encode(to: encoder)
        case .level(let value):
            try container.encode("level", forKey: .type)
            try container.encode(value, forKey: .value)
        case .bye:
            try container.encode("bye", forKey: .type)
        case .error(let code, let message):
            try container.encode("error", forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
        }
    }
}

/// Why the server turned a connection away. Both are fatal to it: the
/// message is there to be read in a log, not acted on.
///
/// An `Error` as well as a wire value: refusing a handshake is what the
/// server's door hands back, and it hands back nothing else.
enum BridgeErrorCode: String, Codable, Error {
    case version, token
}
