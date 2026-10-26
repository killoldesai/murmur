import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

/// Search across transcripts and summaries. Matches design/iphone/Search.dc.html.
struct SearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPad: the note whose preview is showing. nil means the first result.
    @State private var previewID: UUID?
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    @State private var query: String
    @State private var scope: SearchScope = .all
    @FocusState private var focused: Bool

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let results = NoteSearch.search(query, in: notes, scope: scope)
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            if sizeClass == .regular {
                padLayout(results)
            } else {
            VStack(alignment: .leading, spacing: 14) {
                searchRow.murmurEntrance(index: 0)
                scopeChips.murmurEntrance(index: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if trimmed.isEmpty {
                            message("Type a word or phrase to search every transcript and summary on this device.")
                        } else if results.isEmpty {
                            message("No notes match “\(trimmed)”.")
                        } else {
                            Text(NoteSearch.summaryLine(for: results))
                                .font(.footnote)
                                .foregroundStyle(MurmurTheme.Colors.textSecondary)
                            ForEach(results) { result in
                                NavigationLink(value: result.note) { card(result) }
                                    .buttonStyle(MurmurPressStyle())
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
            .padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task { if query.isEmpty { focused = true } }
    }

    // MARK: - iPad: results beside a preview (design/ipad/Search.dc.html)

    private func padLayout(_ results: [SearchResult]) -> some View {
        let current = results.first { $0.id == previewID } ?? results.first
        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                searchRow
                scopeChips
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            Rectangle().fill(MurmurTheme.Colors.border).frame(height: MurmurTheme.Metrics.borderWidth)
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if trimmed.isEmpty {
                            message("Type a word or phrase to search every transcript and summary on this device.")
                        } else if results.isEmpty {
                            message("No notes match “\(trimmed)”.")
                        } else {
                            Text(NoteSearch.summaryLine(for: results))
                                .font(.footnote)
                                .foregroundStyle(MurmurTheme.Colors.textSecondary)
                            ForEach(results) { result in
                                Button { previewID = result.id } label: { card(result) }
                                    .buttonStyle(MurmurPressStyle())
                                    .overlay(
                                        RoundedRectangle(cornerRadius: MurmurTheme.Metrics.cardRadius, style: .continuous)
                                            .strokeBorder(MurmurTheme.Colors.accent, lineWidth: MurmurTheme.Metrics.selectedBorderWidth)
                                            .opacity(result.id == current?.id ? 1 : 0)
                                    )
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(width: 420)
                Rectangle().fill(MurmurTheme.Colors.border).frame(width: MurmurTheme.Metrics.borderWidth)
                preview(current)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func preview(_ result: SearchResult?) -> some View {
        if let result {
            let lines = SearchContext.lines(for: result.note, query: trimmed)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.note.title)
                            .font(MurmurTheme.Fonts.title)
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        Text(NoteSummaryText.headerLine(for: result.note))
                            .font(.subheadline)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                    Spacer(minLength: 8)
                    NavigationLink(value: result.note) {
                        Text("Open note")
                            .font(MurmurTheme.Fonts.body.weight(.bold))
                            .foregroundStyle(MurmurTheme.Colors.onAccent)
                            .padding(.horizontal, 18)
                            .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MurmurTheme.Colors.accent))
                    }
                    .buttonStyle(MurmurPressStyle())
                }
                ScrollView {
                    VStack(spacing: 6) {
                        if lines.isEmpty {
                            message("The match is in this note’s summary.")
                        }
                        ForEach(lines) { line in
                            HStack(alignment: .top, spacing: 16) {
                                Text(line.timestamp)
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(MurmurTheme.Colors.accent)
                                    .frame(width: 56, alignment: .leading)
                                    .padding(.top, 3)
                                Text(Highlight.line(line.text, spans: line.spans))
                                    .font(MurmurTheme.Fonts.body)
                                    .foregroundStyle(line.isMatch ? MurmurTheme.Colors.textPrimary : MurmurTheme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(line.isMatch ? MurmurTheme.Colors.selectedFill : Color.clear))
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        } else {
            Text("Results appear here")
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .accessibilityHidden(true)
                TextField("Search transcripts", text: $query)
                    .font(MurmurTheme.Fonts.body)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .tint(MurmurTheme.Colors.accent)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MurmurTheme.Colors.textTertiary)
                            .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, 14)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MurmurTheme.Colors.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(MurmurTheme.Colors.accent, lineWidth: MurmurTheme.Metrics.selectedBorderWidth)
            )
            Button("Cancel") { dismiss() }
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.accent)
                .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
        }
    }

    private var scopeChips: some View {
        HStack(spacing: 8) {
            ForEach(SearchScope.allCases) { option in
                Chip(option.title, isSelected: scope == option) { scope = option }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(MurmurTheme.Fonts.body)
            .foregroundStyle(MurmurTheme.Colors.textTertiary)
            .padding(.top, 8)
    }

    private func card(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(MurmurTheme.Colors.folder(result.note.folder?.colorIndex ?? 0))
                    .frame(width: 10, height: 10)
                Text(result.note.title)
                    .font(MurmurTheme.Fonts.headline)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(result.countText)
                    .font(MurmurTheme.Fonts.caption)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
            ForEach(result.hits) { hit in
                HStack(alignment: .top, spacing: 10) {
                    Text(hit.label)
                        .font(MurmurTheme.Fonts.caption.monospacedDigit())
                        .foregroundStyle(hit.isSummary ? MurmurTheme.Colors.folder(2) : MurmurTheme.Colors.accent)
                        .frame(minWidth: 38, alignment: .leading)
                        .padding(.top, 2)
                    Text(Highlight.snippet(hit.snippet))
                        .font(.subheadline)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .murmurCard()
        .accessibilityElement(children: .combine)
    }
}
