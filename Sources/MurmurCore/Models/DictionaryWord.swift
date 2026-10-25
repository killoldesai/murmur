import Foundation
import SwiftData

public enum DictionaryWordKind: String, Codable, Sendable, CaseIterable {
    case name
    case term
}

/// A custom vocabulary word. Passed to Whisper as a prompt so it spells names and jargon correctly.
@Model
public final class DictionaryWord {
    public var id: UUID = UUID()
    public var term: String = ""
    var kindRaw: String = DictionaryWordKind.term.rawValue
    public var createdAt: Date = Date()

    public init(term: String, kind: DictionaryWordKind = .term, createdAt: Date = Date()) {
        self.term = term
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
    }

    public var kind: DictionaryWordKind {
        get { DictionaryWordKind(rawValue: kindRaw) ?? .term }
        set { kindRaw = newValue.rawValue }
    }
}
