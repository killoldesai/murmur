import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

/// Temporary home screen so the recorder and transcriber can be tried end to end. It is
/// replaced by the real Library screen in build step 4.
struct DevHomeView: View {
    let services: AppServices

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    /// One full-screen cover whose content switches, so moving from the record screen to the
    /// transcribing screen never needs two covers at once.
    private enum Route: Identifiable {
        case recording(RecordingController)
        case modelDownload
        case transcribing(Note)
        var id: String { "cover" }
    }

    @State private var route: Route?
    @State private var showGallery = false
    @State private var openedNote: Note?
    @State private var recoveredCount = 0

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Murmur")
                        .font(MurmurTheme.Fonts.largeTitle)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    Text("Development build. Record, then Murmur transcribes it on this device.")
                        .font(MurmurTheme.Fonts.body)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)

                    if !services.models.isReady {
                        SecondaryButton("Download speech model", systemImage: "arrow.down.circle") {
                            route = .modelDownload
                        }
                    }

                    PrimaryButton("Start recording", systemImage: "mic.fill") {
                        route = .recording(makeController())
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
                        Button { open(note) } label: {
                            NoteCard(
                                title: note.title,
                                meta: meta(for: note),
                                tint: MurmurTheme.Colors.folder(0)
                            )
                        }
                        .buttonStyle(MurmurPressStyle())
                    }

                    SecondaryButton("Component gallery") { showGallery = true }
                }
                .padding(MurmurTheme.Metrics.screenPadding)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            recoverInterruptedRecordings()
            if services.models.isReady {
                services.queue.start()
            } else {
                route = .modelDownload
            }
        }
        .onChange(of: services.models.isReady) { _, ready in
            if ready { services.queue.start() }
        }
        .fullScreenCover(item: $route) { current in
            switch current {
            case .recording(let controller):
                RecordingScreen(
                    controller: controller,
                    onClose: { route = nil },
                    onFinished: { note in finished(note) }
                )
            case .modelDownload:
                ModelDownloadScreen(manager: services.models, onContinue: { route = nil })
            case .transcribing(let note):
                transcribingScreen(for: note)
            }
        }
        .sheet(isPresented: $showGallery) {
            ComponentGallery()
        }
        .sheet(item: $openedNote) { note in
            DevTranscriptView(note: note)
        }
    }

    // MARK: - Actions

    private func finished(_ note: Note) {
        if services.models.isReady {
            services.queue.start()
            route = .transcribing(note)
        } else {
            // The note stays queued and is transcribed as soon as the model is downloaded.
            route = .modelDownload
        }
    }

    private func open(_ note: Note) {
        switch note.status {
        case .ready: openedNote = note
        case .queued, .transcribing, .failed:
            if services.models.isReady {
                if note.status == .failed { note.status = .queued }
                services.queue.start()
                route = .transcribing(note)
            } else {
                route = .modelDownload
            }
        case .recording: break
        }
    }

    private func transcribingScreen(for note: Note) -> some View {
        let isCurrent = services.queue.currentNoteID == note.id
        let phase: TranscribingScreen.Phase = switch note.status {
        case .ready: .done
        case .failed: .failed(services.queue.lastFailure ?? "Something went wrong. Open the note to try again.")
        default: .working
        }
        return TranscribingScreen(
            phase: phase,
            fraction: isCurrent ? services.queue.fraction : (note.status == .ready ? 1 : 0),
            etaText: isCurrent ? ETAEstimator.text(for: services.queue.etaSeconds) : "Waiting its turn",
            segments: isCurrent ? services.queue.previewSegments : note.segments,
            onLater: { route = nil },
            onOpen: {
                route = nil
                openedNote = note
            }
        )
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

    private func meta(for note: Note) -> String {
        var text = "\(Timecode.format(note.duration)) · \(statusText(note.status))"
        if !note.bookmarks.isEmpty { text += " · \(note.bookmarks.count) bookmarks" }
        return text
    }

    private func statusText(_ status: NoteStatus) -> String {
        switch status {
        case .recording: "Recording"
        case .queued: "Waiting to transcribe"
        case .transcribing: "Transcribing"
        case .ready: "Ready"
        case .failed: "Failed, tap to retry"
        }
    }
}

/// Temporary transcript viewer until the real note screen exists (build step 4).
private struct DevTranscriptView: View {
    let note: Note

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(note.title)
                        .font(MurmurTheme.Fonts.title)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    Text("\(Timecode.format(note.duration)) · \(note.language ?? "unknown language")")
                        .font(MurmurTheme.Fonts.caption)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    if note.segments.isEmpty {
                        Text(note.transcript.isEmpty ? "No speech was found in this recording." : note.transcript)
                            .font(MurmurTheme.Fonts.body)
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    }
                    ForEach(note.segments) { segment in
                        HStack(alignment: .top, spacing: 12) {
                            Text(Timecode.format(segment.start))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(MurmurTheme.Colors.accent)
                                .frame(minWidth: 40, alignment: .leading)
                            Text(segment.text)
                                .font(MurmurTheme.Fonts.body)
                                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MurmurTheme.Metrics.screenPadding)
            }
        }
        .preferredColorScheme(.dark)
    }
}
