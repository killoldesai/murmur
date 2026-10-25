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
