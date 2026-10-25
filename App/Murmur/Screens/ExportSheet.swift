import SwiftUI
import UIKit
import MurmurCore
import MurmurUI

/// Bottom sheet: pick a format and options, then share or copy. Matches design/iphone/Export.dc.html.
struct ExportSheet: View {
    let note: Note
    let files: AudioFileStore
    let onClose: () -> Void

    @State private var format: ExportFormat = .text
    @State private var options = ExportOptions()
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var shared: SharedFile?
    @State private var copied = false

    private var hasSummary: Bool {
        !(note.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Export")
                    .font(MurmurTheme.Fonts.title)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
                        .background(Circle().fill(MurmurTheme.Colors.raised))
                }
                .buttonStyle(MurmurPressStyle())
                .accessibilityLabel("Close")
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(ExportFormat.allCases) { item in
                    formatCard(item)
                }
            }

            optionsCard

            if let errorMessage {
                Text(errorMessage)
                    .font(MurmurTheme.Fonts.caption)
                    .foregroundStyle(MurmurTheme.Colors.record)
            }

            PrimaryButton(copied ? "Copied" : (isPreparing ? "Preparing…" : format.actionTitle),
                          systemImage: format == .copy ? "doc.on.doc" : "square.and.arrow.up") {
                Task { await perform() }
            }
            .disabled(isPreparing)
            .opacity(isPreparing ? 0.6 : 1)
        }
        .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MurmurTheme.Colors.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(MurmurTheme.Colors.surface)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: copied)
        .onChange(of: format) { _, _ in
            copied = false
            errorMessage = nil
        }
        .sheet(item: $shared) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Pieces

    private func formatCard(_ item: ExportFormat) -> some View {
        let selected = item == format
        return Button { format = item } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol(for: item))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(selected ? MurmurTheme.Colors.onAccent : MurmurTheme.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(selected ? MurmurTheme.Colors.accent : MurmurTheme.Colors.raised))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(MurmurTheme.Fonts.body.weight(.bold))
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    Text(item.detail)
                        .font(MurmurTheme.Fonts.caption)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? MurmurTheme.Colors.selectedFill : MurmurTheme.Colors.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? MurmurTheme.Colors.accent : MurmurTheme.Colors.border,
                                  lineWidth: selected ? MurmurTheme.Metrics.selectedBorderWidth : MurmurTheme.Metrics.borderWidth)
            )
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func symbol(for item: ExportFormat) -> String {
        switch item {
        case .text: "doc.text"
        case .subtitles: "captions.bubble"
        case .audio: "music.note"
        case .copy: "doc.on.doc"
        }
    }

    private var optionsCard: some View {
        let active = format.usesTextOptions
        return VStack(spacing: 0) {
            optionRow("Speaker labels", isOn: $options.speakerLabels, enabled: active)
            divider
            optionRow("Timestamps", isOn: $options.timestamps, enabled: active && format != .subtitles)
            divider
            optionRow("Include summary", isOn: $options.summary, enabled: active && hasSummary && format != .subtitles)
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MurmurTheme.Colors.background))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
    }

    private var divider: some View {
        Rectangle().fill(MurmurTheme.Colors.border).frame(height: MurmurTheme.Metrics.borderWidth)
    }

    private func optionRow(_ title: String, isOn: Binding<Bool>, enabled: Bool) -> some View {
        Toggle(title, isOn: isOn)
            .font(MurmurTheme.Fonts.body)
            .foregroundStyle(MurmurTheme.Colors.textPrimary)
            .tint(MurmurTheme.Colors.accent)
            .padding(.horizontal, 14)
            .frame(minHeight: MurmurTheme.Metrics.minTapTarget + 8)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
    }

    // MARK: - Action

    private func perform() async {
        isPreparing = true
        errorMessage = nil
        copied = false
        defer { isPreparing = false }
        do {
            let service = ExportService(files: files)
            switch try await service.prepare(note: note, format: format, options: options) {
            case .text(let text):
                UIPasteboard.general.string = text
                copied = true
            case .file(let url):
                shared = SharedFile(url: url)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn’t prepare the export."
        }
    }
}
