import SwiftUI
import MurmurCore
import MurmurUI

/// The round icon button used in screen headers.
struct HeaderCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .frame(width: MurmurTheme.Metrics.minTapTarget + 2, height: MurmurTheme.Metrics.minTapTarget + 2)
                .background(Circle().fill(MurmurTheme.Colors.surface))
                .overlay(Circle().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityLabel(label)
    }
}

/// Text with accent-filled matches, as in Search and Find & replace.
enum Highlight {
    static func snippet(_ snippet: TextSearch.Snippet) -> AttributedString {
        var text = AttributedString(snippet.pre)
        var word = AttributedString(snippet.word)
        word.backgroundColor = MurmurTheme.Colors.accent
        word.foregroundColor = MurmurTheme.Colors.onAccent
        text += word
        text += AttributedString(snippet.post)
        return text
    }

    /// `spans` are character offsets into `text`. The current match is accent, the others grey.
    static func line(_ text: String, spans: [HighlightSpan]) -> AttributedString {
        var attributed = AttributedString(text)
        for span in spans {
            let characters = attributed.characters
            guard let start = characters.index(characters.startIndex, offsetBy: span.offset, limitedBy: characters.endIndex),
                  let end = characters.index(start, offsetBy: span.length, limitedBy: characters.endIndex) else { continue }
            attributed[start..<end].backgroundColor = span.isCurrent ? MurmurTheme.Colors.accent : MurmurTheme.Colors.raised
            attributed[start..<end].foregroundColor = span.isCurrent ? MurmurTheme.Colors.onAccent : MurmurTheme.Colors.textPrimary
        }
        return attributed
    }
}
