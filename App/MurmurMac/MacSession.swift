import SwiftUI
import SwiftData
import Observation
import MurmurCore
import MurmurUI

enum SidebarItem: Hashable {
    case all, recent, fromWatch, queue
    case folder(UUID)
}

/// Everything the Mac windows share: what is selected, the recording in progress, and the
/// actions the toolbar, menus, menu bar item and hot key all call.
@MainActor
@Observable
final class MacSession {
    let deps: LibraryDependencies
    let container: ModelContainer
    let store: LibraryStore
    let requestMicrophone: () async -> Void

    var sidebar: SidebarItem = .all
    var selectedNoteID: UUID?
    var searchText = ""
    var searchFocusTick = 0
    /// True while the search field is being typed in, so Space is not taken as Play.
    var searchIsFocused = false
    var showInspector = true
    var exportNote: Note?
    var showPaywall = false
    var showModelDownload = false
    var isDropTargeted = false
    var dropCount = 0
    var message: String?
    private(set) var recorder: RecordingController?

    init(deps: LibraryDependencies, container: ModelContainer, requestMicrophone: @escaping () async -> Void = {}) {
        self.deps = deps
        self.container = container
        self.store = LibraryStore(context: container.mainContext, files: deps.files)
        self.requestMicrophone = requestMicrophone
    }

    var context: ModelContext { container.mainContext }
    var isRecording: Bool {
        guard let state = recorder?.state else { return false }
        return state == .recording || state == .paused
    }

    // MARK: Library

    var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        return all.first { $0.id == id }
    }

    /// Opens the export sheet, or the paywall when part of the note is locked.
    func requestExport(_ note: Note) {
        if FreeTier.lockedCount(note.segments, isPro: deps.entitlements.isPro) > 0 {
            showPaywall = true
        } else {
            exportNote = note
        }
    }

    func select(_ note: Note) {
        selectedNoteID = note.id
    }

    func focusSearch() {
        searchFocusTick += 1
    }

    /// Notes for the current sidebar item and search text.
    func visibleNotes(from all: [Note]) -> [Note] {
        var notes: [Note]
        switch sidebar {
        case .all, .queue: notes = all
        case .recent: notes = NoteFilter.recent(all)
        case .fromWatch: notes = NoteFilter.fromWatch(all)
        case .folder(let id): notes = NoteFilter.filter(all, folderID: id)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            notes = notes.filter {
                $0.title.localizedStandardContains(query) || $0.transcript.localizedStandardContains(query)
            }
        }
        return notes
    }

    func title(for item: SidebarItem, folders: [Folder]) -> String {
        switch item {
        case .all: "All notes"
        case .recent: "Recent"
        case .fromWatch: "From Apple Watch"
        case .queue: "Queue"
        case .folder(let id): folders.first { $0.id == id }?.name ?? "Folder"
        }
    }

    // MARK: Recording

    func startRecording() {
        guard recorder == nil else { return }
        guard deps.models.isReady else {
            showModelDownload = true
            return
        }
        let controller = RecordingController(
            engine: deps.makeRecorder(),
            store: RecordingNoteStore(context: context, files: deps.files),
            files: deps.files
        )
        recorder = controller
        Task { await controller.start() }
    }

    /// Stops, queues the note for transcription and selects it.
    func stopRecording() {
        guard let recorder else { return }
        let note = recorder.stop()
        self.recorder = nil
        if let note {
            sidebar = .all
            selectedNoteID = note.id
            deps.queue.start()
        }
    }

    func cancelRecording() {
        recorder?.cancel()
        recorder = nil
    }

    func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    // MARK: Import

    /// Adds audio and video files to the batch queue. Anything else is ignored.
    func importFiles(_ urls: [URL]) {
        let supported = urls.filter { $0.isFileURL && ImportFormats.isSupported($0) }
        guard !supported.isEmpty else {
            message = "Murmur can import audio and video files (MP3, M4A, WAV, MP4, MOV and more)."
            return
        }
        guard deps.models.isReady else {
            showModelDownload = true
            return
        }
        _ = deps.importer.enqueue(supported)
        sidebar = .queue
    }

    func delete(_ note: Note) {
        if selectedNoteID == note.id { selectedNoteID = nil }
        store.delete(note)
    }
}

/// Seconds as "12 min" or "1 h 5 min", for time left.
enum DurationText {
    static func remaining(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if seconds < 60 { return "under 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
