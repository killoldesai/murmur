import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

/// Search across transcripts and summaries. Matches design/iphone/Search.dc.html.
struct SearchScreen: View {
    @Environment(\.dismiss) private var dismiss
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
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task { if query.isEmpty { focused = true } }
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
