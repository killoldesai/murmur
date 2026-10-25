import Foundation
import SwiftData

/// A user folder. Deleting a folder keeps its notes (they become unfiled).
@Model
public final class Folder {
    public var id: UUID = UUID()
    public var name: String = "New folder"
    /// Index into the five folder colours (wraps around).
    public var colorIndex: Int = 0
    public var createdAt: Date = Date()
    public var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Note.folder)
    public var notes: [Note]? = []

    public init(name: String = "New folder", colorIndex: Int = 0, sortOrder: Int = 0) {
        self.name = name
        self.colorIndex = colorIndex
        self.sortOrder = sortOrder
    }
}
