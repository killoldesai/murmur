import Foundation
import SwiftData
import MurmurCore

/// Downloader for the demo: reports 42% and then waits (until cancelled), or finishes at once.
struct DemoDownloader: SpeechModelDownloader {
    let finishes: Bool
    let folder: URL

    func download(_ model: SpeechModel, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if finishes {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            onProgress(1)
            return folder
        }
        onProgress(0.42)
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
        return folder
    }
}

/// First file finishes at once, the second stalls at 46%, the rest wait.
struct DemoConverter: AudioConverting {
    func convert(from source: URL, to destination: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> TimeInterval {
        if source.lastPathComponent.hasPrefix("Customer") {
            FileManager.default.createFile(atPath: destination.path, contents: Data([0]))
            return 18 * 60 + 22
        }
        onProgress(0.46)
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
        return 0
    }
}

/// Sample notes for screenshots. Everything lives in an in-memory store.
@MainActor
enum DemoData {
    static let speakers = ["Alex", "Priya", "Jordan"]

    static func makeContainer(seeded: Bool) -> ModelContainer {
        let container = try! MurmurSchema.makeContainer(inMemory: true)
        guard seeded else { return container }
        let context = container.mainContext
        let now = Date()

        let work = Folder(name: "Work", colorIndex: 0, sortOrder: 0)
        let ideas = Folder(name: "Ideas", colorIndex: 1, sortOrder: 1)
        let school = Folder(name: "School", colorIndex: 2, sortOrder: 2)
        [work, ideas, school].forEach(context.insert)

        let sync = Note(title: "Product sync — Q4 roadmap", createdAt: now.addingTimeInterval(-600), duration: 42 * 60 + 10, source: .recording, status: .ready)
        sync.segments = syncSegments
        sync.transcript = syncSegments.joinedText
        sync.speakerNames = speakers

        let idea = Note(title: "Onboarding idea", createdAt: now.addingTimeInterval(-3600 * 2), duration: 84, source: .watch, status: .ready)
        idea.transcript = "Show the airplane-mode demo first, then let people record."
        idea.segments = [TranscriptSegment(start: 0, end: 5, text: idea.transcript)]

        let bio = Note(title: "Biology 201 — Lecture 8", createdAt: now.addingTimeInterval(-3600 * 26), duration: 72 * 60 + 4, source: .importedFile, status: .ready)
        bio.transcript = "Cellular respiration, starting with glycolysis in the cytoplasm."
        bio.segments = [TranscriptSegment(start: 0, end: 6, text: bio.transcript)]

        [sync, idea, bio].forEach { $0.audioFileName = "demo.caf" }
        let waiting = Note(title: "Recording Oct 25, 9:41 AM", createdAt: now.addingTimeInterval(-60), duration: 125, source: .recording, status: .queued)

        [sync, idea, bio, waiting].forEach(context.insert)
        sync.folder = work
        idea.folder = ideas
        bio.folder = school
        try? context.save()
        return container
    }

    static let syncSegments: [TranscriptSegment] = [
        TranscriptSegment(start: 4, end: 14, text: "Okay, let’s start with the Q4 roadmap. The big question is Watch first or sync first.", speakerIndex: 0),
        TranscriptSegment(start: 15, end: 23, text: "Watch is smaller, and it’s the most requested feature in support emails.", speakerIndex: 1),
        TranscriptSegment(start: 24, end: 32, text: "Sync needs CloudKit migration work. That’s at least three weeks on its own.", speakerIndex: 2),
        TranscriptSegment(start: 33, end: 39, text: "Then Watch first, and we move sync to December.", speakerIndex: 0),
        TranscriptSegment(start: 40, end: 46, text: "I’ll update the timeline and share it by Friday.", speakerIndex: 1),
        TranscriptSegment(start: 47, end: 55, text: "I’ll start the migration spike next week so December holds.", speakerIndex: 2),
    ]

    static func firstReadyNoteID(in container: ModelContainer) -> UUID {
        firstReadyNote(in: container).id
    }

    static func firstReadyNote(in container: ModelContainer) -> Note {
        let notes = (try? container.mainContext.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        return notes.first { $0.status == .ready }!
    }

    static func dependencies(container: ModelContainer, player given: DemoPlayerEngine? = nil, summaries: SummaryService? = nil, entitlements: EntitlementController? = nil) -> LibraryDependencies {
        let player = given ?? DemoPlayerEngine(duration: 42 * 60 + 10)
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-demo-lib-\(UUID().uuidString)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "murmur-demo-\(UUID().uuidString)")!
        // A model folder that already exists, so the demo behaves like a user who has the model.
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("demo", isDirectory: true), withIntermediateDirectories: true)
        defaults.set("demo", forKey: "model.folder.large")
        let models = SpeechModelManager(
            downloader: DemoDownloader(finishes: true, folder: base.appendingPathComponent("demo", isDirectory: true)),
            baseDirectory: base,
            defaults: defaults
        )
        let files = AudioFileStore(directory: base.appendingPathComponent("audio", isDirectory: true))
        return LibraryDependencies(
            models: models,
            queue: TranscriptionQueue(context: container.mainContext, files: files, engineProvider: { nil }),
            importer: ImportQueue(context: container.mainContext, files: files, converter: DemoConverter()),
            files: files,
            makeRecorder: { DemoRecorderEngine() },
            makePlayer: { player },
            summaries: summaries ?? DemoSummaryService(),
            entitlements: entitlements ?? EntitlementController(store: DemoPurchaseStore()),
            settings: AppSettings(defaults: defaults)
        )
    }
}

