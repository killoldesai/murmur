import Foundation

/// The Mac's global "start recording" shortcut. Modifiers use Carbon's bit values so the app can
/// hand them straight to the system hot key API.
public struct RecordShortcut: Equatable, Codable, Sendable {
    public static let command = 256
    public static let shift = 512
    public static let option = 2048
    public static let control = 4096

    /// Virtual key code (15 is the R key).
    public var keyCode: Int
    public var carbonModifiers: Int
    /// The letter or symbol to show, upper case.
    public var key: String

    public init(keyCode: Int, carbonModifiers: Int, key: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.key = key.uppercased()
    }

    /// Control + Option + R.
    public static let `default` = RecordShortcut(keyCode: 15, carbonModifiers: control | option, key: "R")

    /// "⌃⌥R"
    public var display: String {
        var text = ""
        if carbonModifiers & Self.control != 0 { text += "⌃" }
        if carbonModifiers & Self.option != 0 { text += "⌥" }
        if carbonModifiers & Self.shift != 0 { text += "⇧" }
        if carbonModifiers & Self.command != 0 { text += "⌘" }
        return text + key
    }

    /// A global shortcut needs Control, Option or Command, or it would fire while typing.
    public var isValid: Bool {
        carbonModifiers & (Self.control | Self.option | Self.command) != 0 && !key.isEmpty
    }

    public func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func decode(_ raw: String?) -> RecordShortcut? {
        guard let raw, let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(RecordShortcut.self, from: data), value.isValid
        else { return nil }
        return value
    }
}
