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
