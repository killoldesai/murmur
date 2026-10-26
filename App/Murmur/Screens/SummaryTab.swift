import SwiftUI
import MurmurCore
import MurmurUI

/// The Summary tab of the Note screen. Matches design/iphone/Summary.dc.html.
@MainActor
struct SummaryTab: View {
    let note: Note
    let controller: SummaryController
    let onGenerate: () -> Void
    let onToggle: (UUID) -> Void
    let onCopy: () -> Void
    let copied: Bool
    /// Talk-time bars, shown in the iPad summary panel. Empty hides the card.
    var talkTime: [SpeakerShare] = []

    private var summary: NoteSummary? { NoteSummary.decode(note.summary) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                templateChips
                if controller.isGenerating, case .generating(let message) = controller.state {
                    generating(message)
                } else if let summary {
                    summaryCard(summary)
                    if !summary.actionItems.isEmpty { actionCard(summary.actionItems) }
                    if !talkTime.isEmpty { speakersCard }
                    footer(summary)
                } else {
                    empty
                }
                if case .failed(let message) = controller.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(MurmurTheme.Colors.record)
                        .accessibilityLabel("Error: \(message)")
                }
            }
            .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
            .padding(.bottom, 16)
        }
    }

    private var templateChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SummaryTemplate.allCases) { template in
                    Chip(template.title, isSelected: controller.template == template) {
                        controller.template = template
                    }
                    .disabled(controller.isGenerating)
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No summary yet")
                .font(MurmurTheme.Fonts.headline)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
            Text("Pick a style, then create a summary. It’s made on this device with Apple Intelligence, so nothing is uploaded.")
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
            PrimaryButton("Create summary", systemImage: "sparkles", action: onGenerate)
                .disabled(note.segments.isEmpty)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .murmurCard()
    }

    private func generating(_ message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().tint(MurmurTheme.Colors.accent)
            Text(message)
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
            Spacer()
            Button("Cancel") { controller.cancel() }
                .foregroundStyle(MurmurTheme.Colors.accent)
                .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
        }
        .padding(16)
        .murmurCard()
        .accessibilityElement(children: .combine)
    }

    private func summaryCard(_ summary: NoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SUMMARY").murmurSectionLabel()
                Spacer()
                Button(action: onCopy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MurmurTheme.Colors.accent)
                        .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                }
                .accessibilityLabel("Copy summary")
            }
            Text(summary.text)
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            PrimaryButton(controller.isGenerating ? "Working…" : "Regenerate as \(controller.template.title)",
                          systemImage: "arrow.clockwise", action: onGenerate)
        }
        .padding(16)
        .murmurCard()
    }

    private func actionCard(_ items: [ActionItem]) -> some View {
        let done = items.filter(\.done).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACTION ITEMS").murmurSectionLabel()
                Spacer()
                Text("\(done) of \(items.count) done")
                    .font(.footnote)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
            ProgressView(value: Double(done), total: Double(max(items.count, 1)))
                .tint(MurmurTheme.Colors.accent)
                .accessibilityHidden(true)
            ForEach(items) { item in
                Button { onToggle(item.id) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.done ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text)
                                .font(MurmurTheme.Fonts.body)
                                .strikethrough(item.done)
                                .foregroundStyle(item.done ? MurmurTheme.Colors.textTertiary : MurmurTheme.Colors.textPrimary)
                                .multilineTextAlignment(.leading)
                            if let meta = item.metaLine {
                                Text(meta)
                                    .font(.footnote)
                                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: MurmurTheme.Metrics.minTapTarget, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(item.done ? [.isButton, .isSelected] : [.isButton])
                .accessibilityHint("Double tap to mark \(item.done ? "not done" : "done")")
            }
        }
        .padding(16)
        .murmurCard()
    }

    private var speakersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SPEAKERS").murmurSectionLabel()
            ForEach(talkTime) { share in
                HStack(spacing: 10) {
                    Text(share.name)
                        .font(MurmurTheme.Fonts.body)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .frame(width: 80, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(MurmurTheme.Colors.raised)
                            Capsule()
                                .fill(MurmurTheme.Colors.folder(share.index))
                                .frame(width: max(8, proxy.size.width * share.fraction))
                        }
                    }
                    .frame(height: 8)
                    Text("\(share.percent)%")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .frame(minHeight: 28)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(share.name), \(share.percent) percent of the talking")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .murmurCard()
    }

    private func footer(_ summary: NoteSummary) -> some View {
        Label("Generated on-device with Apple Intelligence", systemImage: "sparkles")
            .font(.footnote)
            .foregroundStyle(MurmurTheme.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }
}
