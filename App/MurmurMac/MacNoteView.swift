import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

/// Transcript with playback, plus a toggleable inspector (design/mac/NoteInspector.dc.html).
struct MacNoteView: View {
    let note: Note
    @Bindable var session: MacSession
    @State private var playback: PlaybackController
    @State private var summaryController: SummaryController
    @State private var title: String
    @FocusState private var titleFocused: Bool

    init(note: Note, session: MacSession) {
        self.note = note
        self.session = session
        _playback = State(initialValue: PlaybackController(engine: session.deps.makePlayer(), segments: note.segments))
        _summaryController = State(initialValue: SummaryController(service: session.deps.summaries))
        _title = State(initialValue: note.title)
    }

    private var isPro: Bool { session.deps.entitlements.isPro }
    private var lockedCount: Int { FreeTier.lockedCount(note.segments, isPro: isPro) }
    private var highlighting: Bool { playback.isPlaying || playback.currentTime > 0 }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(MurmurTheme.Colors.border).frame(height: 1)
                transcript
                Rectangle().fill(MurmurTheme.Colors.border).frame(height: 1)
                playerBar
            }
            if session.showInspector {
                Rectangle().fill(MurmurTheme.Colors.border).frame(width: 1)
                MacInspector(note: note, session: session, summaryController: summaryController)
                    .frame(width: MurmurTheme.Mac.inspectorWidth)
            }
        }
        .background(MurmurTheme.Colors.background)
        .task {
            if let name = note.audioFileName {
                playback.load(url: session.deps.files.url(for: name), fallbackDuration: note.duration)
            } else {
                playback.load(url: session.deps.files.url(for: "missing"), fallbackDuration: note.duration)
            }
            playback.start()
        }
        .onDisappear { playback.stop() }
        .background(
            Button("") { playback.toggle() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(titleFocused || session.searchIsFocused)
                .opacity(0)
                .accessibilityHidden(true)
        )
        // Up and Down move between transcript lines (and play from there).
        .background(
            Button("") { playback.step(bySegments: -1) }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(titleFocused || session.searchIsFocused)
                .opacity(0)
                .accessibilityHidden(true)
        )
        .background(
            Button("") { playback.step(bySegments: 1) }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(titleFocused || session.searchIsFocused)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(MurmurTheme.Mac.title)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .focused($titleFocused)
                    .onSubmit { session.store.rename(note, to: title) }
                Text(note.createdAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                     + " · " + Timecode.format(note.duration))
                    .font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
            }
            Spacer()
            toolbarButton("Export", "square.and.arrow.up") { session.requestExport(note) }
            toolbarButton("Inspector", "sidebar.right") { session.showInspector.toggle() }
        }
        .padding(.horizontal, MurmurTheme.Mac.padding)
        .frame(height: 64)
    }

    private func toolbarButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .frame(width: MurmurTheme.Mac.controlHeight, height: MurmurTheme.Mac.controlHeight)
                .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).fill(MurmurTheme.Colors.surface))
                .overlay(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).strokeBorder(MurmurTheme.Colors.border))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: Transcript

    @ViewBuilder private var transcript: some View {
        if note.status != .ready {
            VStack(spacing: 8) {
                if note.status == .transcribing || note.status == .queued { ProgressView() }
                Text(NoteSummaryText.statusText(note.status) ?? "")
                    .font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textSecondary)
                if note.status == .transcribing {
                    Text("\(Int(session.deps.queue.fraction * 100))% · \(RealtimeFactor.text(session.deps.queue.speedFactor))")
                        .font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if note.segments.isEmpty {
            Text(note.transcript.isEmpty ? "No speech found." : note.transcript)
                .font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(MurmurTheme.Mac.padding)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(FreeTier.visible(note.segments, isPro: isPro).enumerated()), id: \.element.id) { index, segment in
                            segmentRow(segment, playing: highlighting && playback.playingIndex == index)
                                .id(segment.id)
                        }
                        if lockedCount > 0 { lockedCard }
                    }
                    .padding(MurmurTheme.Mac.padding)
                }
                .onChange(of: playback.playingIndex) { _, index in
                    guard playback.isPlaying, let index, note.segments.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(note.segments[index].id, anchor: .center) }
                }
            }
        }
    }

    private func segmentRow(_ segment: TranscriptSegment, playing: Bool) -> some View {
        Button { playback.play(segment: segment) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let speaker = segment.speakerIndex {
                        Circle().fill(MurmurTheme.Colors.folder(speaker)).frame(width: 7, height: 7)
                        Text(Speakers.name(at: speaker, in: note.speakerNames)).font(MurmurTheme.Mac.smallBold)
                            .foregroundStyle(MurmurTheme.Colors.folder(speaker))
                    }
                    Text(Timecode.format(segment.start)).font(MurmurTheme.Mac.small.monospacedDigit())
                        .foregroundStyle(MurmurTheme.Colors.textTertiary)
                }
                Text(segment.text).font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.rowRadius).fill(playing ? MurmurTheme.Colors.selectedFill : .clear))
            .overlay(RoundedRectangle(cornerRadius: MurmurTheme.Mac.rowRadius)
                .strokeBorder(playing ? MurmurTheme.Colors.accent : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var lockedCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill").foregroundStyle(MurmurTheme.Colors.accent)
            Text(FreeTier.lockedText(duration: note.duration)).font(MurmurTheme.Mac.bodyBold)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
            Text("Murmur Pro unlocks the full transcript, summaries and export.")
                .font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textSecondary)
            Button("Unlock Murmur Pro") { session.showPaywall = true }
                .buttonStyle(.plain)
                .font(MurmurTheme.Mac.bodyBold).foregroundStyle(MurmurTheme.Colors.onAccent)
                .padding(.horizontal, 14).frame(height: MurmurTheme.Mac.controlHeight)
                .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).fill(MurmurTheme.Colors.accent))
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(MurmurTheme.Colors.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MurmurTheme.Colors.border))
        .padding(.top, 8)
    }

    private var playerBar: some View {
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
        .padding(MurmurTheme.Mac.padding)
        .background(MurmurTheme.Colors.panel)
    }
}

// MARK: - Inspector

struct MacInspector: View {
    let note: Note
    @Bindable var session: MacSession
    @Bindable var summaryController: SummaryController

    private var summary: NoteSummary? { NoteSummary.decode(note.summary) }
    private var isPro: Bool { session.deps.entitlements.isPro }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summarySection
                if let summary, !summary.actionItems.isEmpty { actionItems(summary) }
                talkTime
                fileInfo
            }
            .padding(MurmurTheme.Mac.padding)
        }
        .background(MurmurTheme.Colors.panel)
    }

    // Summary

    @ViewBuilder private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary").murmurSectionLabel()
            if let summary {
                Text(summary.text).font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                HStack {
                    smallButton("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary.plainText, forType: .string)
                    }
                    smallButton("Regenerate") { generate() }
                }
            } else if case .unavailable(let reason) = summaryController.availability {
                Text(reason).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
            } else if summaryController.isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    if case .generating(let text) = summaryController.state {
                        Text(text).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                }
            } else {
                Picker("Template", selection: $summaryController.template) {
                    ForEach(SummaryTemplate.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                smallButton("Create summary", filled: true) { generate() }
                    .disabled(note.segments.isEmpty)
            }
            if case .failed(let message) = summaryController.state {
                Text(message).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.record)
            }
        }
    }

    private func generate() {
        guard isPro || FreeTier.lockedCount(note.segments, isPro: false) == 0 else {
            session.showPaywall = true
            return
        }
        Task {
            if let result = await summaryController.generate(segments: note.segments, speakerNames: note.speakerNames) {
                session.store.setSummary(result, for: note)
            }
        }
    }

    private func smallButton(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(MurmurTheme.Mac.bodyBold)
                .foregroundStyle(filled ? MurmurTheme.Colors.onAccent : MurmurTheme.Colors.textPrimary)
                .padding(.horizontal, 12).frame(height: MurmurTheme.Mac.controlHeight)
                .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius)
                    .fill(filled ? MurmurTheme.Colors.accent : MurmurTheme.Colors.raised))
        }
        .buttonStyle(.plain)
    }

    // Action items

    private func actionItems(_ summary: NoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Action items").murmurSectionLabel()
            ForEach(summary.actionItems) { item in
                Button { session.store.toggleActionItem(item.id, in: note) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.done ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text).font(MurmurTheme.Mac.body)
                                .foregroundStyle(item.done ? MurmurTheme.Colors.textTertiary : MurmurTheme.Colors.textPrimary)
                                .strikethrough(item.done)
                                .multilineTextAlignment(.leading)
                            if let meta = item.metaLine {
                                Text(meta).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.text), \(item.done ? "done" : "not done")")
            }
        }
    }

    // Talk time

    @ViewBuilder private var talkTime: some View {
        let shares = TalkTime.shares(segments: note.segments, names: note.speakerNames)
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Talk time").murmurSectionLabel()
                ForEach(shares) { share in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(share.name).font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textPrimary)
                            Spacer()
                            Text("\(share.percent)%").font(MurmurTheme.Mac.small.monospacedDigit())
                                .foregroundStyle(MurmurTheme.Colors.textTertiary)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(MurmurTheme.Colors.raised)
                                Capsule().fill(MurmurTheme.Colors.folder(share.index))
                                    .frame(width: proxy.size.width * share.fraction)
                            }
                        }
                        .frame(height: 6)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // File info

    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("File info").murmurSectionLabel()
            infoRow("Length", Timecode.format(note.duration))
            infoRow("Source", note.source == .watch ? "Apple Watch" : note.source == .importedFile ? "Imported file" : "Recorded on this Mac")
            infoRow("Language", note.language.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 } ?? "—")
            infoRow("Audio", audioText)
            if let name = note.audioFileName, session.deps.files.exists(name) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([session.deps.files.url(for: name)])
                }
                .buttonStyle(.plain)
                .font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.accent)
                .padding(.top, 2)
            }
        }
    }

    private var audioText: String {
        guard let name = note.audioFileName, session.deps.files.exists(name) else {
            return AudioAvailability.of(note, files: session.deps.files, syncActive: session.deps.settings.isSyncActive) == .onAnotherDevice
                ? "On another device" : "Deleted"
        }
        let url = session.deps.files.url(for: name)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return "\(url.pathExtension.uppercased()) · \(ByteText.format(Int64(size)))"
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
            Spacer()
            Text(value).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textSecondary)
        }
    }
}
