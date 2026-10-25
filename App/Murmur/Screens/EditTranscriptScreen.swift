import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

/// Edit segment text and speakers; split, merge, delete, undo. Matches design/iphone/Edit.dc.html.
struct EditTranscriptScreen: View {
    let note: Note
    let deps: LibraryDependencies
    let playback: PlaybackController
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var editor: TranscriptEditor
    @State private var selectedID: UUID?
    @State private var selection: TextSelection?
    @State private var confirmDiscard = false
    @State private var addingSpeaker = false
    @State private var newSpeakerName = ""
    @State private var speakerRefresh = 0

    init(note: Note, deps: LibraryDependencies, playback: PlaybackController, initialSelection: UUID? = nil, onClose: @escaping () -> Void) {
        self.note = note
        self.deps = deps
        self.playback = playback
        self.onClose = onClose
        _editor = State(initialValue: TranscriptEditor(segments: note.segments))
        _selectedID = State(initialValue: initialSelection)
    }

    private var store: LibraryStore { LibraryStore(context: modelContext, files: deps.files) }

    private var selectedSegment: TranscriptSegment? {
        guard let selectedID, let i = editor.index(of: selectedID) else { return nil }
        return editor.segments[i]
    }

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(editor.segments) { segment in
                                if segment.id == selectedID {
                                    editingCard(segment).id(segment.id)
                                } else {
                                    plainRow(segment).id(segment.id)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: selectedID) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                toolbar
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Discard your edits?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard edits", role: .destructive, action: onClose)
            Button("Keep editing", role: .cancel) {}
        }
        .alert("New speaker", isPresented: $addingSpeaker) {
            TextField("Name", text: $newSpeakerName)
            Button("Add") {
                let name = newSpeakerName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, let id = selectedID {
                    let index = store.addSpeaker(named: name, to: note)
                    editor.setSpeaker(index, for: id)
                    speakerRefresh += 1
                }
                newSpeakerName = ""
            }
            Button("Cancel", role: .cancel) { newSpeakerName = "" }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Button("Cancel") {
                if editor.hasChanges { confirmDiscard = true } else { onClose() }
            }
            .font(MurmurTheme.Fonts.body)
            .foregroundStyle(MurmurTheme.Colors.textSecondary)
            .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
            Spacer()
            Text("Edit transcript")
                .font(MurmurTheme.Fonts.headline)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                if editor.hasChanges {
                    store.applyEdit(editor.segments, to: note)
                    playback.segments = note.segments
                }
                onClose()
            } label: {
                Text("Done")
                    .font(MurmurTheme.Fonts.body.weight(.bold))
                    .foregroundStyle(MurmurTheme.Colors.onAccent)
                    .padding(.horizontal, 16)
                    .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                    .background(Capsule().fill(MurmurTheme.Colors.accent))
            }
            .buttonStyle(MurmurPressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MurmurTheme.Colors.border).frame(height: MurmurTheme.Metrics.borderWidth)
        }
    }

    private func speakerLabel(_ segment: TranscriptSegment) -> (name: String, initial: String, color: Color)? {
        guard let index = segment.speakerIndex else { return nil }
        return (Speakers.name(at: index, in: note.speakerNames),
                Speakers.initial(at: index, in: note.speakerNames),
                MurmurTheme.Colors.folder(index))
    }

    private func plainRow(_ segment: TranscriptSegment) -> some View {
        Button {
            selection = nil
            selectedID = segment.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let label = speakerLabel(segment) {
                        SpeakerBadge(initial: label.initial, color: label.color)
                        Text(label.name)
                            .font(MurmurTheme.Fonts.caption.weight(.semibold))
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    }
                    Text(Timecode.format(segment.start))
                        .font(MurmurTheme.Fonts.caption.monospacedDigit())
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                }
                Text(segment.text)
                    .font(MurmurTheme.Fonts.body)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityHint("Edit this line")
    }

    private func editingCard(_ segment: TranscriptSegment) -> some View {
        let label = speakerLabel(segment)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let label {
                    SpeakerBadge(initial: label.initial, color: label.color)
                    Text(label.name)
                        .font(MurmurTheme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                }
                Text(Timecode.format(segment.start))
                    .font(MurmurTheme.Fonts.caption.monospacedDigit())
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
            TextEditor(
                text: Binding(
                    get: { segment.text },
                    set: { editor.setText($0, for: segment.id) }
                ),
                selection: $selection
            )
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .font(MurmurTheme.Fonts.body)
            .foregroundStyle(MurmurTheme.Colors.textPrimary)
            .frame(minHeight: 84)
            .accessibilityLabel("Segment text")

            VStack(alignment: .leading, spacing: 8) {
                Text("Speaker")
                    .font(MurmurTheme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let count = Speakers.count(names: note.speakerNames, segments: editor.segments)
                        ForEach(0..<count, id: \.self) { index in
                            speakerChip(index: index, selected: segment.speakerIndex == index, id: segment.id)
                        }
                        Button { addingSpeaker = true } label: {
                            Text("+ Add")
                                .font(MurmurTheme.Fonts.caption.weight(.semibold))
                                .foregroundStyle(MurmurTheme.Colors.textSecondary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                                .overlay(Capsule().strokeBorder(MurmurTheme.Colors.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }
                        .buttonStyle(MurmurPressStyle())
                    }
                }
                .id(speakerRefresh)
            }
        }
        .padding(14)
        .murmurCard(selected: true)
    }

    private func speakerChip(index: Int, selected: Bool, id: UUID) -> some View {
        Button {
            editor.setSpeaker(selected ? nil : index, for: id)
        } label: {
            HStack(spacing: 7) {
                SpeakerBadge(initial: Speakers.initial(at: index, in: note.speakerNames), color: MurmurTheme.Colors.folder(index))
                Text(Speakers.name(at: index, in: note.speakerNames))
                    .font(MurmurTheme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
            .background(Capsule().fill(selected ? MurmurTheme.Colors.raised : Color.clear))
            .overlay(Capsule().strokeBorder(selected ? MurmurTheme.Colors.textPrimary : MurmurTheme.Colors.border, lineWidth: 1))
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            tool("arrow.uturn.backward", "Undo", enabled: editor.canUndo) { editor.undo() }
            tool(playback.isPlaying ? "pause.fill" : "play.fill", playback.isPlaying ? "Pause" : "Play", enabled: selectedSegment != nil) {
                if let segment = selectedSegment {
                    if playback.isPlaying { playback.toggle() } else { playback.play(segment: segment) }
                }
            }
            tool("scissors", "Split", enabled: selectedSegment != nil) { split() }
            tool("arrow.triangle.merge", "Merge", enabled: selectedID.map(editor.canMerge) ?? false) {
                if let id = selectedID { editor.merge(id) }
            }
            tool("trash", "Delete", enabled: selectedSegment != nil) {
                if let id = selectedID {
                    let next = editor.index(of: id).flatMap { i in
                        editor.segments.indices.contains(i + 1) ? editor.segments[i + 1].id : nil
                    }
                    editor.delete(id)
                    selectedID = next
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(MurmurTheme.Colors.surface))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func tool(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                Text(label).font(.caption2)
            }
            .foregroundStyle(enabled ? MurmurTheme.Colors.textPrimary : MurmurTheme.Colors.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(MurmurPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Splits at the cursor. With no cursor in the text, splits at the middle word.
    private func split() {
        guard let segment = selectedSegment else { return }
        var offset = segment.text.count / 2
        if let selection, case .selection(let range) = selection.indices {
            offset = segment.text.distance(from: segment.text.startIndex, to: range.lowerBound)
        }
        if let newID = editor.split(segment.id, atCharacterOffset: offset) {
            selection = nil
            selectedID = newID
        }
    }
}
