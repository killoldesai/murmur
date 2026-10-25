import SwiftUI

/// Library list card: coloured dot tile, title, meta line and an optional snippet.
public struct NoteCard: View {
    let title: String
    let meta: String
    let snippet: String?
    let tint: Color

    public init(title: String, meta: String, snippet: String? = nil, tint: Color) {
        self.title = title
        self.meta = meta
        self.snippet = snippet
        self.tint = tint
    }

    public var body: some View {
        HStack(alignment: .top, spacing: MurmurTheme.Metrics.spacingM) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.18))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.headline)
                        .foregroundStyle(tint)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(MurmurTheme.Fonts.headline)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .lineLimit(1)
                Text(meta)
                    .font(MurmurTheme.Fonts.caption)
                    .foregroundStyle(MurmurTheme.Colors.textTertiary)
                if let snippet {
                    Text(snippet)
                        .font(MurmurTheme.Fonts.body)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .murmurCard()
        .accessibilityElement(children: .combine)
    }
}
