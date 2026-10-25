import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

/// Temporary home screen so the recorder can be tried end to end. It is replaced by the real
/// Library screen in build step 4.
struct DevHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    @State private var controller: RecordingController?
    @State private var showGallery = false
    @State private var recoveredCount = 0

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Murmur")
                        .font(MurmurTheme.Fonts.largeTitle)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    Text("Development build. Record to test the microphone; transcription comes next.")
                        .font(MurmurTheme.Fonts.body)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)

                    PrimaryButton("Start recording", systemImage: "mic.fill") {
                        controller = makeController()
                    }

                    if recoveredCount > 0 {
                        Text("Recovered \(recoveredCount) interrupted recording\(recoveredCount == 1 ? "" : "s").")
                            .font(MurmurTheme.Fonts.caption)
                            .foregroundStyle(MurmurTheme.Colors.accent)
                    }

                    Text("Recordings").murmurSectionLabel()
                    if notes.isEmpty {
                        Text("Nothing recorded yet.")
                            .font(MurmurTheme.Fonts.body)
                            .foregroundStyle(MurmurTheme.Colors.textTertiary)
                    }
                    ForEach(notes) { note in
                        NoteCard(
                            title: note.title,
                            meta: "\(Timecode.format(note.duration)) · \(statusText(note.status))"
                                + (note.bookmarks.isEmpty ? "" : " · \(note.bookmarks.count) bookmarks"),
                            tint: MurmurTheme.Colors.folder(0)
                        )
                    }

                    SecondaryButton("Component gallery") { showGallery = true }
                }
                .padding(MurmurTheme.Metrics.screenPadding)
            }
        }
        .preferredColorScheme(.dark)
        .task { recoverInterruptedRecordings() }
        .fullScreenCover(isPresented: Binding(
            get: { controller != nil },
            set: { if !$0 { controller = nil } }
        )) {
            if let controller {
                RecordingScreen(
                    controller: controller,
                    onClose: { self.controller = nil },
                    onFinished: { _ in self.controller = nil }
                )
            }
        }
        .sheet(isPresented: $showGallery) {
            ComponentGallery()
        }
    }

    private func makeController() -> RecordingController {
        RecordingController(
            engine: AVAudioRecorderEngine(),
            store: RecordingNoteStore(context: modelContext, files: .standard),
            files: .standard
        )
    }

    private func recoverInterruptedRecordings() {
        let store = RecordingNoteStore(context: modelContext, files: .standard)
        recoveredCount = (try? store.recoverInterruptedRecordings()) ?? 0
    }

    private func statusText(_ status: NoteStatus) -> String {
        switch status {
        case .recording: "Recording"
        case .queued: "Waiting to transcribe"
        case .transcribing: "Transcribing"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }
}
