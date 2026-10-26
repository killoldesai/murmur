import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

/// Names and terms Whisper should spell correctly. Matches design/iphone/Dictionary.dc.html.
struct DictionaryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DictionaryWord.createdAt, order: .reverse) private var words: [DictionaryWord]

    @State private var draft = ""

    private var store: DictionaryStore { DictionaryStore(context: modelContext) }
    private var canAdd: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HeaderCircleButton(symbol: "chevron.left", label: "Back") { dismiss() }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .murmurEntrance(index: 0)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom dictionary")
                            .font(MurmurTheme.Fonts.title)
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Add names, jargon and acronyms so Murmur spells them right every time.")
                            .font(MurmurTheme.Fonts.body)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                    .padding(.top, 14)
                    .murmurEntrance(index: 1)

                    addRow
                        .padding(.top, 18)
                        .murmurEntrance(index: 2)

                    HStack(alignment: .firstTextBaseline) {
                        Text("YOUR WORDS").murmurSectionLabel()
                        Spacer()
                        Text("\(words.count) word\(words.count == 1 ? "" : "s")")
                            .font(.footnote)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                    .padding(.top, 22)

                    if words.isEmpty {
                        Text("No words yet. Add a name or term above.")
                            .font(MurmurTheme.Fonts.body)
                            .foregroundStyle(MurmurTheme.Colors.textTertiary)
                            .padding(.top, 12)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(words) { word in chip(word) }
                        }
                        .padding(.top, 12)
                    }

                    legend
                        .padding(.top, 28)
                        .murmurEntrance(index: 3)
                }
                .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("Add a word or phrase", text: $draft)
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .tint(MurmurTheme.Colors.accent)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(add)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MurmurTheme.Colors.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(MurmurTheme.Colors.accent, lineWidth: MurmurTheme.Metrics.selectedBorderWidth)
                )
                .accessibilityLabel("New word")
            Button(action: add) {
                Text("Add")
                    .font(MurmurTheme.Fonts.body.weight(.bold))
                    .foregroundStyle(MurmurTheme.Colors.onAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MurmurTheme.Colors.accent))
                    .opacity(canAdd ? 1 : 0.45)
            }
            .buttonStyle(MurmurPressStyle())
            .disabled(!canAdd)
        }
    }

    private func chip(_ word: DictionaryWord) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(MurmurTheme.Colors.folder(word.kind == .name ? 1 : 2))
                .frame(width: 8, height: 8)
                .padding(.trailing, 2)
            Text(word.term)
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
            Button { store.remove(word) } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(MurmurTheme.Colors.textTertiary)
                    .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MurmurPressStyle())
            .accessibilityLabel("Remove \(word.term)")
        }
        .padding(.leading, 14)
        .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
        .background(Capsule().fill(MurmurTheme.Colors.surface))
        .overlay(Capsule().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
        .accessibilityElement(children: .contain)
    }

    private var legend: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                legendRow("Names", color: MurmurTheme.Colors.folder(1))
                legendRow("Terms", color: MurmurTheme.Colors.folder(2))
            }
            Text("Words apply to new transcriptions. Use Find & replace to fix older notes.")
                .font(.footnote)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .murmurCard()
    }

    private func legendRow(_ title: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.footnote).foregroundStyle(MurmurTheme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func add() {
        guard canAdd else { return }
        store.add(draft)
        draft = ""
    }
}
