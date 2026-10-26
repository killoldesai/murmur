import SwiftUI
import UIKit
import SwiftData
import MurmurCore
import MurmurUI

/// A transcribed note with synced playback. Matches design/iphone/Note.dc.html.
@MainActor
struct NoteScreen: View {
    enum Tab { case transcript, summary }

    let note: Note
    let deps: LibraryDependencies
    /// False in the iPad detail column, where there is nothing to go back to.
    let showsBack: Bool
    /// Called after the note is deleted when the screen is not pushed (iPad detail column).
    let onDeleted: (() -> Void)?
    /// iPad full-screen layout: transcript beside a summary panel (design/ipad/Note.dc.html).
    let wide: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var playback: PlaybackController
    @State private var showEdit = false
    @State private var showExport = false
    @State private var renaming = false
    @State private var titleDraft = ""
    @State private var confirmDelete = false
    @State private var tab: Tab
    @State private var summaryController: SummaryController
    @State private var copied = false
    @State private var findReplace: FindReplaceController?
    @State private var showPaywall = false
    @State private var showWide = false

    init(note: Note, deps: LibraryDependencies, initialTab: Tab = .transcript, showsBack: Bool = true, onDeleted: (() -> Void)? = nil, wide: Bool = false) {
        self.note = note
        self.deps = deps
        self.showsBack = showsBack
        self.onDeleted = onDeleted
        self.wide = wide
        _tab = State(initialValue: initialTab)
        _summaryController = State(initialValue: SummaryController(service: deps.summaries))
        _playback = State(initialValue: PlaybackController(engine: deps.makePlayer(), segments: note.segments))
    }

    private var store: LibraryStore { LibraryStore(context: modelContext, files: deps.files) }

    private var isHighlighting: Bool { playback.isPlaying || playback.currentTime > 0 }

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            if wide {
                wideLayout
            } else {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .murmurEntrance(index: 0)
                titleBlock
                    .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
                    .padding(.top, 14)
                    .murmurEntrance(index: 1)
                if showsTabs {
                    tabSwitch
                        .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
                        .padding(.top, 12)
                }
                if tab == .summary && showsTabs {
                    SummaryTab(
                        note: note,
                        controller: summaryController,
                        onGenerate: { gated { generateSummary() } },
                        onToggle: { store.toggleActionItem($0, in: note) },
                        onCopy: copySummary,
                        copied: copied
                    )
                    .padding(.top, 10)
                    SecondaryButton("Export", systemImage: "square.and.arrow.up") { gated { showExport = true } }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                } else {
                    transcript
                        .padding(.top, 10)
                    if note.audioFileName != nil {
                        playbackPanel
                    } else {
                        Label("Audio was deleted after transcribing", systemImage: "trash")
                            .font(.footnote)
                            .foregroundStyle(MurmurTheme.Colors.textTertiary)
                            .padding(.vertical, 14)
                    }
                }
            }
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let audio = note.audioFileName {
                playback.load(url: deps.files.url(for: audio), fallbackDuration: note.duration)
                playback.start()
            }
        }
        .onDisappear { playback.stop() }
        .fullScreenCover(isPresented: $showEdit) {
            EditTranscriptScreen(note: note, deps: deps, playback: playback) { showEdit = false }
        }
        .fullScreenCover(
            isPresented: Binding(get: { findReplace != nil }, set: { if !$0 { findReplace = nil } }),
            onDismiss: { playback.segments = note.segments }
        ) {
            if let controller = findReplace {
                FindReplaceScreen(controller: controller, speakerNames: note.speakerNames) { findReplace = nil }
            }
        }
        .fullScreenCover(isPresented: $showWide) {
            NoteScreen(note: note, deps: deps, wide: true)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallScreen(controller: deps.entitlements) { showPaywall = false }
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(note: note, files: deps.files) { showExport = false }
        }
        .alert("Rename note", isPresented: $renaming) {
            TextField("Title", text: $titleDraft)
            Button("Save") { store.rename(note, to: titleDraft) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete note and audio", role: .destructive) {
                playback.stop()
                // Delete after the screen has left, so nothing reads a deleted note.
                let store = self.store
                let doomed = note
                if let onDeleted { onDeleted() } else { dismiss() }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    store.delete(doomed)
                }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The recording and its transcript are removed from this device. This can’t be undone.")
        }
    }

    private var hasSummaryPanel: Bool { showsTabs }

    private var wideLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                titleBlock
                    .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
                    .padding(.top, 14)
                transcript.padding(.top, 10)
                if note.audioFileName != nil {
                    playbackPanel
                } else {
                    Label("Audio was deleted after transcribing", systemImage: "trash")
                        .font(.footnote)
                        .foregroundStyle(MurmurTheme.Colors.textTertiary)
                        .padding(.vertical, 14)
                }
            }
            if hasSummaryPanel {
                Rectangle().fill(MurmurTheme.Colors.border).frame(width: MurmurTheme.Metrics.borderWidth)
                SummaryTab(
                    note: note,
                    controller: summaryController,
                    onGenerate: { gated { generateSummary() } },
                    onToggle: { store.toggleActionItem($0, in: note) },
                    onCopy: copySummary,
                    copied: copied,
                    talkTime: TalkTime.shares(segments: note.segments, names: note.speakerNames)
                )
                .padding(.top, 16)
                .frame(width: 380)
                .background(MurmurTheme.Colors.panel)
            }
        }
    }

    private var playbackPanel: some View {
                PlaybackPanel(
                    progress: playback.progress,
                    timeText: playback.timeText,
                    isPlaying: playback.isPlaying,
                    speedLabel: playback.speedLabel,
                    isEnabled: playback.loadError == nil,
                    onSeek: { playback.seek(toFraction: $0) },
                    onToggle: { playback.toggle() },
                    onSkip: { playback.skip(by: $0) },
                    onSpeed: { playback.cycleSpeed() }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .murmurEntrance(index: 3)
    }

    private var showsTabs: Bool {
        if case .available = summaryController.availability { return true }
        return NoteSummary.decode(note.summary) != nil
    }

    private var tabSwitch: some View {
        HStack(spacing: 4) {
            tabButton("Transcript", systemImage: "text.alignleft", selected: tab == .transcript) { tab = .transcript }
            tabButton("Summary", systemImage: "sparkles", selected: tab == .summary) { tab = .summary }
        }
        .padding(4)
        .background(Capsule().fill(MurmurTheme.Colors.surface))
        .overlay(Capsule().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
    }

    private func tabButton(_ title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(MurmurTheme.Fonts.body.weight(.semibold))
                .foregroundStyle(selected ? MurmurTheme.Colors.onAccent : MurmurTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: MurmurTheme.Metrics.minTapTarget)
                .background(Capsule().fill(selected ? MurmurTheme.Colors.accent : Color.clear))
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func generateSummary() {
        let segments = note.segments.sorted { $0.start < $1.start }
        let names = note.speakerNames
        let template = summaryController.template
        Task { @MainActor in
            guard let result = await summaryController.generate(segments: segments, speakerNames: names) else { return }
            var summary = result
            summary.template = template
            store.setSummary(summary, for: note)
        }
    }

    /// Notes longer than the free limit need Pro for anything that uses the whole transcript.
    private var isLimited: Bool {
        FreeTier.lockedCount(note.segments, isPro: deps.entitlements.isPro) > 0
    }

    private func gated(_ action: () -> Void) {
        if isLimited { showPaywall = true } else { action() }
    }

    private func openFindReplace() {
        findReplace = FindReplaceController(
            note: note,
            library: store,
            dictionary: DictionaryStore(context: modelContext)
        )
    }

    private func copySummary() {
        guard let text = NoteSummary.plainText(from: note.summary) else { return }
        UIPasteboard.general.string = text
        Haptics.tap(deps.settings)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            if showsBack {
                circleButton("chevron.left", label: "Back to library") { dismiss() }
            }
            Spacer()
            if !showsBack && !wide && showsTabs {
                circleButton("sparkles", label: "Open with summary panel") {
                    playback.stop()
                    showWide = true
                }
            }
            circleButton("pencil", label: "Edit transcript") { gated { showEdit = true } }
                .disabled(note.segments.isEmpty)
            circleButton("square.and.arrow.up", label: "Export") { gated { showExport = true } }
            Menu {
                Button("Find & replace", systemImage: "text.magnifyingglass") { gated { openFindReplace() } }
                    .disabled(note.segments.isEmpty)
                Button("Rename", systemImage: "pencil") {
                    titleDraft = note.title
                    renaming = true
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                circleLabel("ellipsis")
            }
            .accessibilityLabel("More")
        }
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(symbol) }
            .buttonStyle(MurmurPressStyle())
            .accessibilityLabel(label)
    }

    private func circleLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(MurmurTheme.Colors.textPrimary)
            .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
            .background(Circle().fill(MurmurTheme.Colors.surface))
            .overlay(Circle().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.title)
                .font(MurmurTheme.Fonts.title)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(NoteSummaryText.headerLine(for: note))
                .font(.footnote)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
            if let error = playback.loadError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(MurmurTheme.Colors.record)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("The rest is locked", systemImage: "lock.fill")
                .font(MurmurTheme.Fonts.headline)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
            Text(FreeTier.lockedText(duration: note.duration) + " Murmur Pro unlocks the full transcript, summaries, export and editing.")
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
            PrimaryButton("Unlock Murmur Pro", systemImage: "sparkles") { showPaywall = true }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .murmurCard()
        .padding(.top, 6)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if note.segments.isEmpty {
                        Text(note.transcript.isEmpty ? "No speech was found in this recording." : note.transcript)
                            .font(MurmurTheme.Fonts.body)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    ForEach(Array(FreeTier.visible(note.segments, isPro: deps.entitlements.isPro).enumerated()), id: \.element.id) { index, segment in
                        Button { playback.play(segment: segment) } label: {
                            TranscriptRow(
                                speaker: segment.speakerIndex.map { Speakers.name(at: $0, in: note.speakerNames) },
                                speakerColor: MurmurTheme.Colors.folder(segment.speakerIndex ?? 0),
                                timestamp: Timecode.format(segment.start),
                                text: segment.text,
                                state: isHighlighting && playback.playingIndex == index ? .playing : .normal
                            )
                        }
                        .buttonStyle(MurmurPressStyle())
                        .id(segment.id)
                    }
                    if isLimited { lockedCard }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .onChange(of: playback.playingIndex) { _, index in
                guard playback.isPlaying, let index, note.segments.indices.contains(index) else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                    proxy.scrollTo(note.segments[index].id, anchor: .center)
                }
            }
        }
    }
}

/// Lets the interactive swipe-back gesture work while the system navigation bar is hidden.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
