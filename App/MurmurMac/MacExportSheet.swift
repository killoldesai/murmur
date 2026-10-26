import SwiftUI
import UniformTypeIdentifiers
import MurmurCore
import MurmurUI

enum MacExportFormat: String, CaseIterable, Identifiable {
    case text, subtitles, audio, markdown
    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .subtitles: "Subtitles"
        case .audio: "Audio"
        case .markdown: "Markdown"
        }
    }

    var detail: String {
        switch self {
        case .text: ".txt · plain transcript"
        case .subtitles: ".srt · timed captions"
        case .audio: ".m4a · the recording"
        case .markdown: ".md · headings and a checklist"
        }
    }

    var symbol: String {
        switch self {
        case .text: "doc.text"
        case .subtitles: "captions.bubble"
        case .audio: "waveform"
        case .markdown: "number"
        }
    }
}

/// Export dialog (design/mac/Export.dc.html): format, include options, then Save or Reveal in Finder.
struct MacExportSheet: View {
    let note: Note
    let session: MacSession
    @Environment(\.dismiss) private var dismiss
    @State private var format: MacExportFormat = .text
    @State private var speakerLabels = true
    @State private var timestamps = false
    @State private var includeSummary = true
    @State private var working = false
    @State private var errorText: String?

    private var hasSummary: Bool { NoteSummary.decode(note.summary) != nil }
    private var textual: Bool { format != .audio }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export “\(note.title)”").font(MurmurTheme.Mac.title).foregroundStyle(MurmurTheme.Colors.textPrimary).lineLimit(1)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(MacExportFormat.allCases) { option in
                    Button { format = option } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.symbol).frame(width: 22)
                                .foregroundStyle(format == option ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).font(MurmurTheme.Mac.bodyBold).foregroundStyle(MurmurTheme.Colors.textPrimary)
                                Text(option.detail).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(format == option ? MurmurTheme.Colors.selectedFill : MurmurTheme.Colors.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(format == option ? MurmurTheme.Colors.accent : MurmurTheme.Colors.border, lineWidth: format == option ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(format == option ? .isSelected : [])
                }
            }
            if textual {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Include").murmurSectionLabel()
                    Toggle("Speaker names", isOn: $speakerLabels)
                    Toggle("Timestamps", isOn: $timestamps)
                    Toggle("Summary and action items", isOn: $includeSummary).disabled(!hasSummary)
                }
                .toggleStyle(.checkbox)
                .font(MurmurTheme.Mac.body)
            }
            if let errorText {
                Text(errorText).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.record)
            }
            HStack {
                if textual {
                    Button("Copy text") { copyText() }.buttonStyle(.plain)
                        .foregroundStyle(MurmurTheme.Colors.accent).font(MurmurTheme.Mac.body)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Reveal in Finder") { Task { await export(reveal: true) } }.disabled(working)
                Button("Save…") { Task { await export(reveal: false) } }
                    .keyboardShortcut(.defaultAction).disabled(working)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(MurmurTheme.Colors.background)
        .preferredColorScheme(.dark)
    }

    private var options: ExportOptions {
        ExportOptions(speakerLabels: speakerLabels, timestamps: timestamps, summary: includeSummary && hasSummary)
    }

    private func copyText() {
        let text = format == .markdown ? Exporter.markdown(for: note, options: options) : Exporter.text(for: note, options: options)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        dismiss()
    }

    /// Builds the file in a temporary folder, then saves it where the person chooses or shows it.
    private func export(reveal: Bool) async {
        working = true
        errorText = nil
        defer { working = false }
        let service = ExportService(files: session.deps.files)
        do {
            let url: URL
            switch format {
            case .markdown:
                url = try service.prepareMarkdown(note: note, options: options)
            case .text, .subtitles, .audio:
                let kind: ExportFormat = format == .text ? .text : format == .subtitles ? .subtitles : .audio
                guard case .file(let made) = try await service.prepare(note: note, format: kind, options: options) else { return }
                url = made
            }
            if reveal {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                dismiss()
                return
            }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
