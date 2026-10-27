import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MurmurCore
import MurmurUI

/// The main window: 52 pt header, sidebar, note list and note detail (design/mac/Main.dc.html).
struct MacMainView: View {
    @Bindable var session: MacSession
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    @FocusState private var searchFocused: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(MurmurTheme.Colors.border).frame(height: 1)
            HStack(spacing: 0) {
                MacSidebar(session: session, notes: notes, folders: folders, openSettings: { openSettings() })
                    .frame(width: MurmurTheme.Mac.sidebarWidth)
                Rectangle().fill(MurmurTheme.Colors.border).frame(width: 1)
                content
            }
        }
        .background(MurmurTheme.Colors.background)
        .overlay { if session.isDropTargeted { MacDropOverlay(count: session.dropCount) } }
        .dropDestination(for: URL.self) { urls, _ in
            session.importFiles(urls)
            return true
        } isTargeted: { targeted in
            session.isDropTargeted = targeted
        }
        .sheet(item: $session.exportNote) { note in
            MacExportSheet(note: note, session: session)
        }
        .sheet(isPresented: $session.showPaywall) {
            MacPaywallView(entitlements: session.deps.entitlements, onClose: { session.showPaywall = false })
        }
        .sheet(isPresented: $session.showModelDownload) {
            MacModelDownloadView(manager: session.deps.models) {
                session.showModelDownload = false
                session.deps.queue.start()
            }
        }
        .alert("Murmur", isPresented: Binding(get: { session.message != nil }, set: { if !$0 { session.message = nil } })) {
            Button("OK") { session.message = nil }
        } message: {
            Text(session.message ?? "")
        }
        .onChange(of: session.searchFocusTick) { _, _ in searchFocused = true }
        .onChange(of: searchFocused) { _, focused in session.searchIsFocused = focused }
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: MurmurTheme.Mac.trafficLightsInset)
            Text(session.title(for: session.sidebar, folders: folders))
                .font(MurmurTheme.Mac.bodyBold)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
            Spacer()
            headerButton("Import", systemImage: "square.and.arrow.down") { importWithPanel() }
            searchField
            Button {
                session.startRecording()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                    Text("Record")
                    Text(session.deps.settings.recordShortcut.display).opacity(0.7)
                }
                .font(MurmurTheme.Mac.bodyBold)
                .foregroundStyle(MurmurTheme.Colors.onAccent)
                .padding(.horizontal, 12)
                .frame(height: MurmurTheme.Mac.controlHeight)
                .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).fill(MurmurTheme.Colors.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record")
        }
        .padding(.trailing, MurmurTheme.Mac.padding)
        .frame(height: MurmurTheme.Mac.headerHeight)
        .background(MurmurTheme.Colors.panel)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(MurmurTheme.Colors.textTertiary)
            TextField("Search", text: $session.searchText)
                .textFieldStyle(.plain)
                .font(MurmurTheme.Mac.body)
                .focused($searchFocused)
            if !session.searchText.isEmpty {
                Button { session.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(MurmurTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: MurmurTheme.Mac.controlHeight)
        .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).fill(MurmurTheme.Colors.surface))
        .overlay(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).strokeBorder(MurmurTheme.Colors.border))
    }

    private func headerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(MurmurTheme.Mac.body)
            .foregroundStyle(MurmurTheme.Colors.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: MurmurTheme.Mac.controlHeight)
            .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).fill(MurmurTheme.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).strokeBorder(MurmurTheme.Colors.border))
        }
        .buttonStyle(.plain)
    }

    private func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie]
        panel.prompt = "Import"
        if panel.runModal() == .OK { session.importFiles(panel.urls) }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if session.sidebar == .queue {
            MacQueueView(session: session, notes: notes)
        } else {
            let visible = session.visibleNotes(from: notes)
            HStack(spacing: 0) {
                MacNoteList(session: session, notes: visible, folders: folders, hasAnyNotes: !notes.isEmpty)
                    .frame(width: MurmurTheme.Mac.listWidth)
                Rectangle().fill(MurmurTheme.Colors.border).frame(width: 1)
                detail(in: visible)
            }
        }
    }

    @ViewBuilder private func detail(in visible: [Note]) -> some View {
        if let id = session.selectedNoteID, let note = notes.first(where: { $0.id == id }) {
            MacNoteView(note: note, session: session)
                .id(note.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 30)).foregroundStyle(MurmurTheme.Colors.textTertiary)
                Text("Select a note").font(MurmurTheme.Mac.bodyBold).foregroundStyle(MurmurTheme.Colors.textSecondary)
                Text("Or press \(session.deps.settings.recordShortcut.display) to start recording.")
                    .font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Sidebar

struct MacSidebar: View {
    @Bindable var session: MacSession
    let notes: [Note]
    let folders: [Folder]
    let openSettings: () -> Void
    @State private var newFolderName = ""
    @State private var addingFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("Library")
                    row(.all, "All notes", "tray.full", count: notes.count)
                    row(.recent, "Recent", "clock", count: nil)
                    row(.fromWatch, "From Apple Watch", "applewatch", count: nil)
                    HStack {
                        sectionLabel("Folders")
                        Spacer()
                        Button { addingFolder = true } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(MurmurTheme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New folder")
                        .padding(.trailing, 10)
                    }
                    ForEach(folders) { folder in
                        row(.folder(folder.id), folder.name, "folder.fill",
                            count: NoteFilter.filter(notes, folderID: folder.id).count,
                            tint: MurmurTheme.Colors.folder(folder.colorIndex))
                            .contextMenu {
                                Button("Delete folder", role: .destructive) {
                                    if session.sidebar == .folder(folder.id) { session.sidebar = .all }
                                    session.store.deleteFolder(folder)
                                }
                            }
                    }
                }
                .padding(10)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                queueRow
                Button(action: openSettings) {
                    rowLabel("Settings", "gearshape", count: nil, selected: false, tint: nil)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
        .background(MurmurTheme.Colors.panel)
        .alert("New folder", isPresented: $addingFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") {
                _ = session.store.createFolder(name: newFolderName)
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
    }

    private var queueRow: some View {
        let pending = notes.filter { $0.status == .queued || $0.status == .transcribing }.count
            + session.deps.importer.items.filter { $0.state != .done }.count
        return Button { session.sidebar = .queue } label: {
            rowLabel(pending > 0 ? "Queue · \(pending) working" : "Queue", "list.bullet.rectangle",
                     count: nil, selected: session.sidebar == .queue, tint: nil)
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).murmurSectionLabel().padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
    }

    private func row(_ item: SidebarItem, _ title: String, _ symbol: String, count: Int?, tint: Color? = nil) -> some View {
        Button { session.sidebar = item } label: {
            rowLabel(title, symbol, count: count, selected: session.sidebar == item, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(_ title: String, _ symbol: String, count: Int?, selected: Bool, tint: Color?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(tint ?? (selected ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textSecondary))
            Text(title).font(MurmurTheme.Mac.body)
                .foregroundStyle(selected ? MurmurTheme.Colors.textPrimary : MurmurTheme.Colors.textSecondary)
            Spacer(minLength: 0)
            if let count {
                Text("\(count)").font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: MurmurTheme.Mac.rowHeight)
        .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.rowRadius).fill(selected ? MurmurTheme.Colors.selectedFill : .clear))
        .contentShape(Rectangle())
    }
}

// MARK: - Note list

struct MacNoteList: View {
    @Bindable var session: MacSession
    let notes: [Note]
    let folders: [Folder]
    let hasAnyNotes: Bool

    var body: some View {
        Group {
            if notes.isEmpty {
                VStack(spacing: 8) {
                    Text(hasAnyNotes ? "No matching notes" : "No notes yet")
                        .font(MurmurTheme.Mac.bodyBold).foregroundStyle(MurmurTheme.Colors.textSecondary)
                    Text(hasAnyNotes ? "Try a different search or folder." : "Record, or drop audio files on this window.")
                        .font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(DaySections.make(from: notes)) { section in
                            Text(section.title).murmurSectionLabel().padding(.horizontal, 8).padding(.top, 10)
                            ForEach(section.notes) { note in
                                MacNoteRow(note: note, selected: session.selectedNoteID == note.id)
                                    .onTapGesture { session.select(note) }
                                    .onDrag { dragProvider(for: note) }
                                    .contextMenu { contextMenu(for: note) }
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(MurmurTheme.Colors.background)
    }

    /// Dragging a note to Finder, Mail or another app hands over its transcript as a `.txt` file.
    /// Locked (free-tier) or unfinished notes are not draggable.
    private func dragProvider(for note: Note) -> NSItemProvider {
        guard note.status == .ready,
              FreeTier.lockedCount(note.segments, isPro: session.deps.entitlements.isPro) == 0,
              let url = try? ExportService(files: session.deps.files).prepareTextFile(note: note),
              let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
        return provider
    }

    @ViewBuilder private func contextMenu(for note: Note) -> some View {
        Menu("Move to folder") {
            Button("No folder") { session.store.move(note, to: nil) }
            ForEach(folders) { folder in
                Button(folder.name) { session.store.move(note, to: folder) }
            }
        }
        Button("Export…") { session.exportNote = note }
        Divider()
        Button("Delete", role: .destructive) { session.delete(note) }
    }
}

struct MacNoteRow: View {
    let note: Note
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(note.title).font(MurmurTheme.Mac.bodyBold)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                Text(Timecode.format(note.duration)).font(MurmurTheme.Mac.small.monospacedDigit())
                    .foregroundStyle(MurmurTheme.Colors.textTertiary)
            }
            Text(NoteSummaryText.metaLine(for: note)).font(MurmurTheme.Mac.small)
                .foregroundStyle(MurmurTheme.Colors.textTertiary)
            if let status = NoteSummaryText.statusText(note.status) {
                Text(status).font(MurmurTheme.Mac.small)
                    .foregroundStyle(note.status == .failed ? MurmurTheme.Colors.record : MurmurTheme.Colors.accent)
            } else if let snippet = NoteSummaryText.snippet(for: note, limit: 90) {
                Text(snippet).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textSecondary).lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.rowRadius + 3).fill(selected ? MurmurTheme.Colors.selectedFill : MurmurTheme.Colors.surface))
        .overlay(RoundedRectangle(cornerRadius: MurmurTheme.Mac.rowRadius + 3)
            .strokeBorder(selected ? MurmurTheme.Colors.accent : MurmurTheme.Colors.border, lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Drop overlay

struct MacDropOverlay: View {
    let count: Int

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.opacity(0.92)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill").font(.system(size: 40)).foregroundStyle(MurmurTheme.Colors.accent)
                Text(count > 0 ? "Drop to add \(count) file\(count == 1 ? "" : "s")" : "Drop audio or video files to transcribe")
                    .font(MurmurTheme.Mac.title).foregroundStyle(MurmurTheme.Colors.textPrimary)
                Text("MP3, M4A, WAV, MP4, MOV and more · they stay on this Mac")
                    .font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
            .padding(40)
            .frame(maxWidth: 520)
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(MurmurTheme.Colors.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
            .padding(40)
        }
        .allowsHitTesting(false)
    }
}
