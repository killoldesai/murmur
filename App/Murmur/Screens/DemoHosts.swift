import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

/// Shows the record screen with a fake microphone and an in-memory store. Used by CI to
/// screenshot the screen (the simulator has no microphone). Launch with `-screen recording`
/// or `-screen recordingPaused`.
@MainActor
struct DemoRecordingHost: View {
    let startPaused: Bool
    private let container: ModelContainer
    @State private var controller: RecordingController

    init(startPaused: Bool) {
        self.startPaused = startPaused
        let container = try! MurmurSchema.makeContainer(inMemory: true)
        self.container = container
        let files = AudioFileStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("murmur-demo", isDirectory: true)
        )
        _controller = State(initialValue: RecordingController(
            engine: DemoRecorderEngine(),
            store: RecordingNoteStore(context: container.mainContext, files: files),
            files: files
        ))
    }

    var body: some View {
        RecordingScreen(controller: controller, onClose: {}, onFinished: { _ in })
            .task {
                guard startPaused else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                controller.pause()
            }
    }
}

// MARK: - Model download and transcribing demos (CI screenshots)

/// Downloader for the demo: reports 42% and then waits (until cancelled), or finishes at once.
private struct DemoDownloader: SpeechModelDownloader {
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

@MainActor
struct DemoModelDownloadHost: View {
    enum Mode { case choosing, downloading, done }
    let mode: Mode
    @State private var manager: SpeechModelManager

    init(mode: Mode) {
        self.mode = mode
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-demo-models-\(UUID().uuidString)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "murmur-demo-\(UUID().uuidString)")!
        _manager = State(initialValue: SpeechModelManager(
            downloader: DemoDownloader(finishes: mode == .done, folder: base.appendingPathComponent("demo", isDirectory: true)),
            baseDirectory: base,
            defaults: defaults
        ))
    }

    var body: some View {
        ModelDownloadScreen(manager: manager, onContinue: {})
            .task {
                guard mode != .choosing else { return }
                manager.start()
            }
    }
}

struct DemoTranscribingScreen: View {
    let done: Bool

    private let segments = [
        TranscriptSegment(start: 4, end: 9, text: "Okay, let’s start with the Q4 roadmap."),
        TranscriptSegment(start: 11, end: 17, text: "The big question is Watch first or sync first."),
        TranscriptSegment(start: 19, end: 25, text: "Watch is smaller and users keep asking for it."),
    ]

    var body: some View {
        TranscribingScreen(
            phase: done ? .done : .working,
            fraction: done ? 1 : 0.45,
            etaText: ETAEstimator.text(for: 31),
            segments: segments,
            onLater: {},
            onOpen: {}
        )
    }
}

// MARK: - Library, note and edit demos (CI screenshots)

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

    static func firstReadyNote(in container: ModelContainer) -> Note {
        let notes = (try? container.mainContext.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        return notes.first { $0.status == .ready }!
    }

    static func dependencies(container: ModelContainer, player given: DemoPlayerEngine? = nil, summaries: SummaryService? = nil) -> LibraryDependencies {
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
            summaries: summaries ?? DemoSummaryService()
        )
    }
}

@MainActor
struct DemoLibraryHost: View {
    private let container: ModelContainer
    private let deps: LibraryDependencies

    init(empty: Bool) {
        let container = DemoData.makeContainer(seeded: !empty)
        self.container = container
        self.deps = DemoData.dependencies(container: container)
    }

    var body: some View {
        LibraryScreen(deps: deps)
            .modelContainer(container)
    }
}

@MainActor
struct DemoNoteHost: View {
    let edit: Bool
    var summaryTab = false
    private let container: ModelContainer
    private let player: DemoPlayerEngine
    private let deps: LibraryDependencies
    private let note: Note
    @State private var playback: PlaybackController

    init(edit: Bool, summaryTab: Bool = false) {
        self.edit = edit
        self.summaryTab = summaryTab
        let container = DemoData.makeContainer(seeded: true)
        let player = DemoPlayerEngine(duration: 42 * 60 + 10)
        player.currentTime = 16
        player.play()
        self.container = container
        self.player = player
        self.deps = DemoData.dependencies(container: container, player: player)
        let note = DemoData.firstReadyNote(in: container)
        if summaryTab { note.summary = DemoSummaryService.sample.encoded() }
        self.note = note
        let playback = PlaybackController(engine: player, segments: note.segments)
        playback.load(url: URL(fileURLWithPath: "/demo"))
        _playback = State(initialValue: playback)
    }

    var body: some View {
        Group {
            if edit {
                EditTranscriptScreen(note: note, deps: deps, playback: playback, initialSelection: note.segments[1].id, onClose: {})
            } else {
                NavigationStack { NoteScreen(note: note, deps: deps, initialTab: summaryTab ? .summary : .transcript) }
            }
        }
        .modelContainer(container)
        .task {
            // Let the fake player's clock run so the highlighted line and scrubber move.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                player.advance(by: 0.1)
                playback.tick()
            }
        }
    }
}

// MARK: - Import and export demos (CI screenshots)

/// First file finishes at once, the second stalls at 46%, the rest wait.
private struct DemoConverter: AudioConverting {
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

@MainActor
struct DemoImportHost: View {
    private let container: ModelContainer
    private let deps: LibraryDependencies

    init() {
        let container = DemoData.makeContainer(seeded: false)
        self.container = container
        self.deps = DemoData.dependencies(container: container)
    }

    var body: some View {
        ImportScreen(importer: deps.importer)
            .modelContainer(container)
            .task {
                // Started here, not in init: SwiftUI may create this view more than once, and a
                // discarded copy must not leave work running against a freed store.
                guard deps.importer.items.isEmpty else { return }
                deps.importer.enqueue([
                    URL(fileURLWithPath: "/tmp/Customer interview — Maria.mp4"),
                    URL(fileURLWithPath: "/tmp/Voice memo 14.m4a"),
                    URL(fileURLWithPath: "/tmp/Podcast ep 12 raw.mp3"),
                ])
            }
    }
}

@MainActor
struct DemoExportHost: View {
    private let container: ModelContainer
    private let note: Note
    private let files: AudioFileStore
    @State private var showing = true

    init() {
        let container = DemoData.makeContainer(seeded: true)
        self.container = container
        self.note = DemoData.firstReadyNote(in: container)
        self.files = DemoData.dependencies(container: container).files
    }

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 6) {
                Text(note.title).font(MurmurTheme.Fonts.title).foregroundStyle(MurmurTheme.Colors.textPrimary)
                Text(NoteSummaryText.headerLine(for: note)).font(.footnote).foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(MurmurTheme.Metrics.screenPadding)
        }
        .sheet(isPresented: $showing) {
            ExportSheet(note: note, files: files) { showing = false }
        }
        .modelContainer(container)
    }
}
