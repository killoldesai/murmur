import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

/// Home screen: notes grouped by day, folder chips, record button. Matches
/// design/iphone/Library.dc.html and Empty.dc.html.
struct LibraryScreen: View {
    let deps: LibraryDependencies

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]

    /// One full-screen cover whose content switches, so moving from the record screen to the
    /// transcribing screen never needs two covers at once.
    private enum Route: Identifiable {
        case recording(RecordingController)
        case modelDownload
        case transcribing(Note)
        var id: String { "cover" }
    }

    @State private var route: Route?
    @State private var path: [Note] = []
    @State private var selectedFolderID: UUID?
    @State private var recoveredCount = 0
    @State private var showImport = false
    @State private var showSearch = false
    @State private var showDictionary = false

    @State private var newFolderName = ""
    @State private var showNewFolder = false
    @State private var renameTarget: Note?
    @State private var renameText = ""
    @State private var deleteTarget: Note?

    private var store: LibraryStore { LibraryStore(context: modelContext, files: deps.files) }
    private var visibleNotes: [Note] { NoteFilter.filter(notes, folderID: selectedFolderID) }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                MurmurTheme.Colors.background.ignoresSafeArea()
                if notes.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Note.self) { note in
                NoteScreen(note: note, deps: deps)
            }
            .navigationDestination(isPresented: $showImport) {
                ImportScreen(importer: deps.importer)
            }
            .navigationDestination(isPresented: $showSearch) {
                SearchScreen()
            }
            .navigationDestination(isPresented: $showDictionary) {
                DictionaryScreen()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            recoverInterruptedRecordings()
            if deps.models.isReady {
                deps.queue.start()
            } else {
                route = .modelDownload
            }
        }
        .onOpenURL { url in
            // "Share → Murmur" and "Open in Murmur" from other apps. Files copied into the
            // app's Inbox are removed after import.
            deps.importer.enqueue([url], deleteSourcesAfter: url.path.contains("/Inbox/"))
            showImport = true
        }
        .onChange(of: deps.models.isReady) { _, ready in
            if ready { deps.queue.start() }
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
                ModelDownloadScreen(manager: deps.models, onContinue: { route = nil })
            case .transcribing(let note):
                transcribingScreen(for: note)
            }
        }
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                if let folder = store.createFolder(name: newFolderName) { selectedFolderID = folder.id }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert("Rename note", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let renameTarget { store.rename(renameTarget, to: renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete note and audio", role: .destructive) {
                if let deleteTarget { store.delete(deleteTarget) }
                deleteTarget = nil
            }
            Button("Keep", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("The recording and its transcript are removed from this device. This can’t be undone.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Greeting.text())
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                Text("Murmur")
                    .font(MurmurTheme.Fonts.largeTitle)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            HStack(spacing: 8) {
                HeaderCircleButton(symbol: "magnifyingglass", label: "Search") { showSearch = true }
                HeaderCircleButton(symbol: "character.book.closed", label: "Custom dictionary") { showDictionary = true }
                HeaderCircleButton(symbol: "square.and.arrow.down", label: "Import a file") { showImport = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header.murmurEntrance(index: 0)
                if !deps.models.isReady { downloadPrompt }
                folderChips.murmurEntrance(index: 1)
                if recoveredCount > 0 {
                    Text("Recovered \(recoveredCount) interrupted recording\(recoveredCount == 1 ? "" : "s").")
                        .font(MurmurTheme.Fonts.caption)
                        .foregroundStyle(MurmurTheme.Colors.accent)
                }
                if visibleNotes.isEmpty {
                    Text("No notes in this folder yet.")
                        .font(MurmurTheme.Fonts.body)
                        .foregroundStyle(MurmurTheme.Colors.textTertiary)
                        .padding(.top, 12)
                }
                ForEach(Array(DaySections.make(from: visibleNotes).enumerated()), id: \.element.id) { sectionIndex, section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title).murmurSectionLabel()
                        ForEach(section.notes) { note in
                            row(for: note)
                        }
                    }
                    .murmurEntrance(index: sectionIndex + 2)
                }
            }
            .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private var downloadPrompt: some View {
        SecondaryButton("Download speech model", systemImage: "arrow.down.circle") {
            route = .modelDownload
        }
    }

    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip("All", isSelected: selectedFolderID == nil) { selectedFolderID = nil }
                ForEach(folders) { folder in
                    Chip(folder.name, isSelected: selectedFolderID == folder.id) { selectedFolderID = folder.id }
                        .contextMenu {
                            Button("Delete folder", role: .destructive) {
                                if selectedFolderID == folder.id { selectedFolderID = nil }
                                store.deleteFolder(folder)
                            }
                        }
                }
                Button { showNewFolder = true } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
                        .background(Capsule().fill(MurmurTheme.Colors.surface))
                        .overlay(Capsule().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
                }
                .buttonStyle(MurmurPressStyle())
                .accessibilityLabel("New folder")
            }
        }
    }

    @ViewBuilder
    private func row(for note: Note) -> some View {
        let card = NoteCard(
            title: note.title,
            meta: Timecode.format(note.duration) + " · " + NoteSummaryText.metaLine(for: note),
            snippet: NoteSummaryText.snippet(for: note) ?? NoteSummaryText.statusText(note.status),
            tint: MurmurTheme.Colors.folder(note.folder?.colorIndex ?? 0)
        )
        Group {
            if note.status == .ready {
                NavigationLink(value: note) { card }
            } else {
                Button { openPending(note) } label: { card }
            }
        }
        .buttonStyle(MurmurPressStyle())
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameText = note.title
                renameTarget = note
            }
            Menu("Move to folder", systemImage: "folder") {
                Button("No folder") { store.move(note, to: nil) }
                ForEach(folders) { folder in
                    Button(folder.name) { store.move(note, to: folder) }
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = note }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
                .padding(.top, 16)
                .murmurEntrance(index: 0)
            Spacer()
            VStack(spacing: 26) {
                IdleBars().murmurEntrance(index: 1)
                VStack(spacing: 10) {
                    Text("It’s quiet in here")
                        .font(MurmurTheme.Fonts.title)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    Text("Tap the button to record your first note, or bring in a file you already have.")
                        .font(MurmurTheme.Fonts.body)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                    Button { showImport = true } label: {
                        Label("Import a file", systemImage: "square.and.arrow.down")
                            .font(MurmurTheme.Fonts.body.weight(.semibold))
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                            .padding(.horizontal, 18)
                            .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                            .background(Capsule().fill(MurmurTheme.Colors.surface))
                            .overlay(Capsule().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
                    }
                    .buttonStyle(MurmurPressStyle())
                    .padding(.top, 4)
                    if !deps.models.isReady {
                        SecondaryButton("Download speech model", systemImage: "arrow.down.circle") {
                            route = .modelDownload
                        }
                        .padding(.top, 8)
                    }
                }
                .murmurEntrance(index: 2)
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            RecordButton { route = .recording(makeController()) }
            Label("Stays on your iPhone", systemImage: "lock.fill")
                .font(MurmurTheme.Fonts.caption)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(MurmurTheme.Colors.background)
        .overlay(alignment: .top) {
            Rectangle().fill(MurmurTheme.Colors.border).frame(height: MurmurTheme.Metrics.borderWidth)
        }
    }

    // MARK: - Actions

    private func finished(_ note: Note) {
        if deps.models.isReady {
            deps.queue.start()
            route = .transcribing(note)
        } else {
            // The note stays queued and is transcribed as soon as the model is downloaded.
            route = .modelDownload
        }
    }

    private func openPending(_ note: Note) {
        guard note.status != .recording else { return }
        guard deps.models.isReady else {
            route = .modelDownload
            return
        }
        if note.status == .failed { note.status = .queued }
        deps.queue.start()
        route = .transcribing(note)
    }

    private func transcribingScreen(for note: Note) -> some View {
        let isCurrent = deps.queue.currentNoteID == note.id
        let phase: TranscribingScreen.Phase = switch note.status {
        case .ready: .done
        case .failed: .failed(deps.queue.lastFailure ?? "Something went wrong. Tap the note to try again.")
        default: .working
        }
        return TranscribingScreen(
            phase: phase,
            fraction: isCurrent ? deps.queue.fraction : (note.status == .ready ? 1 : 0),
            etaText: isCurrent ? ETAEstimator.text(for: deps.queue.etaSeconds) : "Waiting its turn",
            segments: isCurrent ? deps.queue.previewSegments : note.segments,
            onLater: { route = nil },
            onOpen: {
                route = nil
                path.append(note)
            }
        )
    }

    private func makeController() -> RecordingController {
        RecordingController(
            engine: deps.makeRecorder(),
            store: RecordingNoteStore(context: modelContext, files: deps.files),
            files: deps.files
        )
    }

    private func recoverInterruptedRecordings() {
        let store = RecordingNoteStore(context: modelContext, files: deps.files)
        recoveredCount = (try? store.recoverInterruptedRecordings()) ?? 0
    }
}

/// Idle bars on the empty screen; the middle one is accent. They sway unless Reduce Motion is on.
private struct IdleBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let heights: [CGFloat] = [14, 22, 34, 26, 46, 60, 72, 60, 46, 26, 34, 22, 14]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(heights.indices, id: \.self) { i in
                    let sway = reduceMotion ? 1 : 0.8 + 0.2 * sin(t * 2.8 - Double(i) * 0.5)
                    Capsule()
                        .fill(i == 6 ? MurmurTheme.Colors.accent : MurmurTheme.Colors.raised)
                        .frame(width: 6, height: heights[i] * sway)
                }
            }
            .frame(width: 220, height: 150)
            .murmurCard()
        }
        .accessibilityHidden(true)
    }
}
