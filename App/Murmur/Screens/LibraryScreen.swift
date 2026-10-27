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

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedNoteID: UUID?
    @State private var route: Route?
    @State private var path: [Note] = []
    @State private var selectedFolderID: UUID?
    @State private var recoveredCount = 0
    @State private var showImport = false
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showFolders = false
    /// The "From Watch" smart folder is selected (instead of a real folder).
    @State private var watchOnly = false

    @State private var newFolderName = ""
    @State private var showNewFolder = false
    @State private var renameTarget: Note?
    @State private var renameText = ""
    @State private var deleteTarget: Note?

    private var store: LibraryStore { LibraryStore(context: modelContext, files: deps.files) }
    private var visibleNotes: [Note] {
        watchOnly ? NoteFilter.fromWatch(notes) : NoteFilter.filter(notes, folderID: selectedFolderID)
    }

    var body: some View {
        shared(layout)
    }

    @ViewBuilder
    private var layout: some View {
        if sizeClass == .regular {
            padLayout
        } else {
            phoneLayout
        }
    }

    private var phoneLayout: some View {
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
            .navigationDestination(isPresented: $showSettings) {
                SettingsScreen(deps: deps)
            }
        }
    }

    /// Behaviour both layouts share: launch tasks, the record / download / transcribe cover and the
    /// rename, delete and new-folder prompts.
    private func shared<Content: View>(_ content: Content) -> some View {
        content
            .preferredColorScheme(.dark)
        .task {
            recoverInterruptedRecordings()
            if deps.models.isReady {
                deps.queue.start()
            } else {
                route = .modelDownload
            }
        }
        .task {
            // Reads what the Apple ID owns (this also restores purchases on a fresh install) and
            // keeps listening for renewals and refunds.
            await deps.entitlements.start()
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
                HeaderCircleButton(symbol: "square.and.arrow.down", label: "Import a file") { showImport = true }
                HeaderCircleButton(symbol: "gearshape", label: "Settings") { showSettings = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header.murmurEntrance(index: 0)
                if !deps.models.isReady { downloadPrompt }
                if deps.settings.newWatchRecordings > 0 { watchBanner }
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
                        HStack {
                            Text(section.title).murmurSectionLabel()
                            Spacer()
                            if sectionIndex == 0 {
                                Button { showFolders = true } label: {
                                    Label("All folders", systemImage: "folder")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(MurmurTheme.Colors.accent)
                                        .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                                }
                                .buttonStyle(MurmurPressStyle())
                            }
                        }
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
                Chip("All", isSelected: selectedFolderID == nil && !watchOnly) { selectedFolderID = nil; watchOnly = false }
                ForEach(folders) { folder in
                    Chip(folder.name, isSelected: selectedFolderID == folder.id && !watchOnly) { selectedFolderID = folder.id; watchOnly = false }
                        .contextMenu {
                            Button("Delete folder", role: .destructive) {
                                if selectedFolderID == folder.id { selectedFolderID = nil }
                                store.deleteFolder(folder)
                            }
                        }
                }
                if notes.contains(where: { $0.source == .watch }) {
                    Chip("From Watch", isSelected: watchOnly) { watchOnly = true; selectedFolderID = nil }
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
        SwipeToDelete(onDelete: { deleteTarget = note }) {
            Group {
                if note.status == .ready {
                    NavigationLink(value: note) { card }
                } else {
                    Button { openPending(note) } label: { card }
                }
            }
            .buttonStyle(MurmurPressStyle())
        }
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
            RecordButton {
                Haptics.tap(deps.settings)
                route = .recording(makeController())
            }
            Label(deps.settings.isSyncActive ? "Synced with your iCloud" : "Stays on your iPhone",
                  systemImage: deps.settings.isSyncActive ? "icloud.fill" : "lock.fill")
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

    private var watchBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.headline)
                .foregroundStyle(MurmurTheme.Colors.accent)
                .accessibilityHidden(true)
            Text(WatchBanner.text(count: deps.settings.newWatchRecordings))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("View") {
                watchOnly = true
                selectedFolderID = nil
                deps.settings.clearNewWatchRecordings()
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(MurmurTheme.Colors.accent)
            .frame(minWidth: MurmurTheme.Metrics.minTapTarget, minHeight: MurmurTheme.Metrics.minTapTarget)
            Button { deps.settings.clearNewWatchRecordings() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(MurmurTheme.Colors.textTertiary)
                    .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .murmurCard(selected: true)
    }

    // MARK: - Actions

    private func chooseFolder(_ card: FolderCard) {
        switch card.kind {
        case .folder(let id):
            selectedFolderID = id
            watchOnly = false
        case .fromWatch:
            selectedFolderID = nil
            watchOnly = true
        }
    }

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
                open(note)
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
        recoveredCount = (try? store.recoverInterruptedRecordings(skippingRemote: deps.settings.isSyncActive)) ?? 0
        if deps.settings.isSyncActive {
            LibraryStore(context: modelContext, files: deps.files).removeOrphanedAudio()
        }
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

// MARK: - iPad: sidebar, note list and note detail (design/ipad/Library.dc.html)

extension LibraryScreen {
    fileprivate var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    /// Opens a finished note: pushed on iPhone, shown in the detail column on iPad.
    fileprivate func open(_ note: Note) {
        if sizeClass == .regular {
            selectedNoteID = note.id
        } else {
            path.append(note)
        }
    }

    fileprivate var padLayout: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
                .background(MurmurTheme.Colors.panel)
                .overlay(alignment: .trailing) { divider }
            noteColumn
                .frame(width: 360)
                .overlay(alignment: .trailing) { divider }
            detail
                .frame(maxWidth: .infinity)
        }
        .background(MurmurTheme.Colors.background.ignoresSafeArea())
        .task {
            if selectedNoteID == nil {
                selectedNoteID = visibleNotes.first { $0.status == .ready }?.id
            }
        }
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                SearchScreen()
                    .navigationDestination(for: Note.self) { NoteScreen(note: $0, deps: deps, wide: true) }
            }
        }
        .sheet(isPresented: $showImport) {
            NavigationStack { ImportScreen(importer: deps.importer) }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsScreen(deps: deps) }
        }
    }

    private var divider: some View {
        Rectangle().fill(MurmurTheme.Colors.border).frame(width: MurmurTheme.Metrics.borderWidth)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Murmur")
                .font(MurmurTheme.Fonts.title)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 10)
                .padding(.bottom, 18)
            Text("Library").murmurSectionLabel().padding(.horizontal, 10).padding(.bottom, 4)
            sidebarRow(title: "All notes", count: notes.count, systemImage: "text.alignleft", color: nil,
                       selected: selectedFolderID == nil) { selectedFolderID = nil }
            HStack {
                Text("Folders").murmurSectionLabel()
                Spacer()
                Button { showNewFolder = true } label: {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
                }
                .accessibilityLabel("New folder")
            }
            .padding(.leading, 10)
            .padding(.top, 14)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(folders) { folder in
                        sidebarRow(title: folder.name, count: folder.notes?.count ?? 0, systemImage: nil,
                                   color: MurmurTheme.Colors.folder(folder.colorIndex),
                                   selected: selectedFolderID == folder.id) { selectedFolderID = folder.id }
                            .contextMenu {
                                Button("Delete folder", role: .destructive) {
                                    if selectedFolderID == folder.id { selectedFolderID = nil }
                                    store.deleteFolder(folder)
                                }
                            }
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 10) {
                PrimaryButton("New recording", systemImage: "mic.fill") {
                    Haptics.tap(deps.settings)
                    route = .recording(makeController())
                }
                HStack(spacing: 8) {
                    SecondaryButton("Import", systemImage: "square.and.arrow.down") { showImport = true }
                    HeaderCircleButton(symbol: "gearshape", label: "Settings") { showSettings = true }
                }
                Label(deps.settings.isSyncActive ? "Synced with your iCloud" : "Stays on your iPad",
                      systemImage: deps.settings.isSyncActive ? "icloud.fill" : "lock.fill")
                    .font(MurmurTheme.Fonts.caption)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 36)
        .padding(.bottom, 20)
    }

    private func sidebarRow(title: String, count: Int, systemImage: String?, color: Color?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(selected ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textSecondary)
                        .frame(width: 18)
                } else if let color {
                    RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10).padding(.horizontal, 4)
                }
                Text(title)
                    .font(MurmurTheme.Fonts.body.weight(selected ? .semibold : .regular))
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(count)").font(MurmurTheme.Fonts.caption).foregroundStyle(MurmurTheme.Colors.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? MurmurTheme.Colors.raised : Color.clear))
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var noteColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(folders.first { $0.id == selectedFolderID }?.name ?? "All notes")
                    .font(MurmurTheme.Fonts.title)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(visibleNotes.count)").font(.footnote).foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
            Button { showSearch = true } label: {
                Label("Search transcripts", systemImage: "magnifyingglass")
                    .font(MurmurTheme.Fonts.body)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: MurmurTheme.Metrics.minTapTarget, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(MurmurTheme.Colors.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
            }
            .buttonStyle(MurmurPressStyle())
            if !deps.models.isReady { downloadPrompt }
            if notes.isEmpty {
                VStack(spacing: 8) {
                    Text("It’s quiet in here").font(MurmurTheme.Fonts.headline).foregroundStyle(MurmurTheme.Colors.textPrimary)
                    Text("Record your first note, or import a file you already have.")
                        .font(MurmurTheme.Fonts.body).foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleNotes) { note in
                        padRow(for: note)
                    }
                }
                .padding(.bottom, 16)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 36)
    }

    @ViewBuilder
    private func padRow(for note: Note) -> some View {
        let selected = note.id == selectedNoteID
        Button {
            if note.status == .ready { selectedNoteID = note.id } else { openPending(note) }
        } label: {
            NoteCard(
                title: note.title,
                meta: Timecode.format(note.duration) + " · " + NoteSummaryText.metaLine(for: note),
                snippet: NoteSummaryText.snippet(for: note) ?? NoteSummaryText.statusText(note.status),
                tint: MurmurTheme.Colors.folder(note.folder?.colorIndex ?? 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MurmurTheme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(MurmurTheme.Colors.accent, lineWidth: MurmurTheme.Metrics.selectedBorderWidth)
                    .opacity(selected ? 1 : 0)
            )
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
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

    @ViewBuilder
    private var detail: some View {
        if let note = selectedNote {
            NoteScreen(note: note, deps: deps, showsBack: false, onDeleted: { selectedNoteID = nil })
                .id(note.id)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "waveform").font(.largeTitle).foregroundStyle(MurmurTheme.Colors.textTertiary)
                Text("Select a note").font(MurmurTheme.Fonts.headline).foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
