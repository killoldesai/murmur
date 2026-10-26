import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import MurmurCore
import MurmurUI

/// Pick audio or video to transcribe; shows the import queue. Matches design/iphone/Import.dc.html.
struct ImportScreen: View {
    let importer: ImportQueue

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isDropTargeted = false
    @State private var showFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var notice: String?

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            if sizeClass == .regular {
                padLayout
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                                .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
                                .background(Circle().fill(MurmurTheme.Colors.surface))
                                .overlay(Circle().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
                        }
                        .buttonStyle(MurmurPressStyle())
                        .accessibilityLabel("Back to library")
                        Spacer()
                    }
                    .murmurEntrance(index: 0)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Import audio or video")
                            .font(MurmurTheme.Fonts.title)
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("MP3, M4A, WAV, MP4 and MOV. Transcribed on-device.")
                            .font(MurmurTheme.Fonts.body)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                    .padding(.top, 14)
                    .murmurEntrance(index: 1)

                    HStack(spacing: 10) {
                        Button { showFiles = true } label: {
                            sourceTile("folder", "Files", tint: MurmurTheme.Colors.folder(4))
                        }
                        .buttonStyle(MurmurPressStyle())
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .videos) {
                            sourceTile("photo.on.rectangle", "Videos in Photos", tint: MurmurTheme.Colors.folder(1))
                        }
                        .buttonStyle(MurmurPressStyle())
                    }
                    .padding(.top, 18)
                    .murmurEntrance(index: 2)

                    HStack(spacing: 14) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(MurmurTheme.Colors.accent)
                        Text("Or tap **Share → Murmur** in any app, like Voice Memos, Zoom or WhatsApp.")
                            .font(.subheadline)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: MurmurTheme.Metrics.cardRadius, style: .continuous)
                            .strokeBorder(MurmurTheme.Colors.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    )
                    .padding(.top, 12)
                    .murmurEntrance(index: 3)

                    HStack {
                        Text("Queue").murmurSectionLabel()
                        Spacer()
                        Text(importer.summary)
                            .font(.footnote)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 8) {
                        if importer.items.isEmpty {
                            Text("Files you add show up here while they’re prepared.")
                                .font(MurmurTheme.Fonts.body)
                                .foregroundStyle(MurmurTheme.Colors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        ForEach(importer.items) { item in
                            ImportRow(item: item)
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let skipped = importer.enqueue(urls)
                if skipped > 0 { notice = "\(skipped) file\(skipped == 1 ? " was" : "s were") skipped: only audio and video can be imported." }
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                        importer.enqueue([movie.url], deleteSourcesAfter: true)
                    }
                }
                photoItems = []
            }
        }
        .alert("Some files were skipped", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: - iPad: drop zone beside the queue (design/ipad/Import.dc.html)

    private var padLayout: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                            .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
                            .background(Circle().fill(MurmurTheme.Colors.surface))
                            .overlay(Circle().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
                    }
                    .buttonStyle(MurmurPressStyle())
                    .accessibilityLabel("Back to library")
                    Text("Import audio or video")
                        .font(MurmurTheme.Fonts.title)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button("Browse Files") { showFiles = true }
                        .buttonStyle(PadPillStyle())
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .videos) {
                        Text("Photos & videos")
                    }
                    .buttonStyle(PadPillStyle())
                }
                .murmurEntrance(index: 0)

                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(MurmurTheme.Colors.accent)
                    Text("Drop files here")
                        .font(MurmurTheme.Fonts.title)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    Text("Drag from Files or any app in Split View. Drop several at once and Murmur queues them.")
                        .font(MurmurTheme.Fonts.body)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Text("MP3 · M4A · WAV · MP4 · MOV")
                        .font(.footnote)
                        .foregroundStyle(MurmurTheme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(isDropTargeted ? MurmurTheme.Colors.selectedFill : MurmurTheme.Colors.panel))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(isDropTargeted ? MurmurTheme.Colors.accent : MurmurTheme.Colors.textTertiary,
                                      style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                )
                .dropDestination(for: URL.self) { urls, _ in
                    let skipped = importer.enqueue(urls.filter(\.isFileURL))
                    if skipped > 0 { notice = "\(skipped) file\(skipped == 1 ? " was" : "s were") skipped: only audio and video can be imported." }
                    return !urls.isEmpty
                } isTargeted: { isDropTargeted = $0 }
                .accessibilityLabel("Drop files here to import")
                .murmurEntrance(index: 1)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Queue")
                        .font(MurmurTheme.Fonts.headline)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    Spacer()
                    Text(importer.summary)
                        .font(.footnote)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                }
                ScrollView {
                    VStack(spacing: 8) {
                        if importer.items.isEmpty {
                            Text("Files you add show up here while they’re prepared.")
                                .font(MurmurTheme.Fonts.body)
                                .foregroundStyle(MurmurTheme.Colors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(importer.items) { ImportRow(item: $0) }
                    }
                }
                Spacer(minLength: 0)
                Text("Files transcribe one at a time on this iPad. You can keep using Murmur while the queue runs.")
                    .font(.footnote)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .murmurCard()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
            .frame(width: 360)
            .background(MurmurTheme.Colors.panel)
            .overlay(alignment: .leading) {
                Rectangle().fill(MurmurTheme.Colors.border).frame(width: MurmurTheme.Metrics.borderWidth)
            }
        }
    }

    private func sourceTile(_ symbol: String, _ label: String, tint: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(MurmurTheme.Colors.background)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))
            Text(label)
                .font(MurmurTheme.Fonts.caption.weight(.semibold))
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .murmurCard()
    }
}

/// Small rounded button in the iPad import header.
private struct PadPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MurmurTheme.Fonts.body.weight(.semibold))
            .foregroundStyle(MurmurTheme.Colors.textPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MurmurTheme.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct ImportRow: View {
    let item: ImportItem

    private var progress: Double {
        switch item.state {
        case .waiting: 0
        case .converting(let f): f
        case .done: 1
        case .failed: 0
        }
    }

    private var statusText: String {
        switch item.state {
        case .waiting: "Waiting"
        case .converting(let f): "\(Int(f * 100))%"
        case .done: item.duration.map { "\(Timecode.format($0)) · Done" } ?? "Done"
        case .failed(let message): message
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(item.extensionLabel)
                .font(.system(.caption2, weight: .heavy))
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MurmurTheme.Colors.raised))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(statusText)
                        .font(MurmurTheme.Fonts.caption.monospacedDigit())
                        .foregroundStyle(isFailed ? MurmurTheme.Colors.record : MurmurTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MurmurTheme.Colors.raised)
                        Capsule().fill(MurmurTheme.Colors.accent)
                            .frame(width: proxy.size.width * progress)
                            .animation(.linear(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 5)
            }

            trailing
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .murmurCard()
        .accessibilityElement(children: .combine)
    }

    private var isFailed: Bool {
        if case .failed = item.state { return true }
        return false
    }

    @ViewBuilder
    private var trailing: some View {
        switch item.state {
        case .done:
            Image(systemName: "checkmark")
                .font(.caption.weight(.heavy))
                .foregroundStyle(MurmurTheme.Colors.onAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(MurmurTheme.Colors.accent))
        case .converting:
            ProgressView().tint(MurmurTheme.Colors.accent)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(MurmurTheme.Colors.record)
        case .waiting:
            Image(systemName: "clock").foregroundStyle(MurmurTheme.Colors.textTertiary)
        }
    }
}

/// A video picked in Photos, copied to a temporary file so it can be converted.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString)-\(received.file.lastPathComponent)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}
