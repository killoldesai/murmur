import SwiftUI
import MurmurCore
import MurmurUI

/// Batch queue: files with length, progress and speed, plus totals (design/mac/Queue.dc.html).
struct MacQueueView: View {
    @Bindable var session: MacSession
    let notes: [Note]

    private var queue: TranscriptionQueue { session.deps.queue }
    private var importer: ImportQueue { session.deps.importer }

    /// Notes still being worked on, plus imported files finished in the last day.
    private var rows: [Note] {
        let cutoff = Date().addingTimeInterval(-86_400)
        return notes
            .filter { $0.status == .queued || $0.status == .transcribing || $0.status == .failed
                || ($0.status == .ready && $0.source == .importedFile && $0.createdAt > cutoff) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let stats = QueueStats.make(notes: notes, currentETA: queue.etaSeconds, speed: queue.speedFactor)
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch queue").font(MurmurTheme.Mac.title).foregroundStyle(MurmurTheme.Colors.textPrimary)
                    Text(totalsText(stats)).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
                }
                Spacer()
                Button(queue.isRunning ? "Pause queue" : "Resume queue") {
                    if queue.isRunning { queue.cancel() } else { queue.start() }
                }
                .buttonStyle(.plain)
                .font(MurmurTheme.Mac.bodyBold).foregroundStyle(MurmurTheme.Colors.textPrimary)
                .padding(.horizontal, 12).frame(height: MurmurTheme.Mac.controlHeight)
                .background(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).fill(MurmurTheme.Colors.surface))
                .overlay(RoundedRectangle(cornerRadius: MurmurTheme.Mac.controlRadius).strokeBorder(MurmurTheme.Colors.border))
            }
            .padding(MurmurTheme.Mac.padding)
            Rectangle().fill(MurmurTheme.Colors.border).frame(height: 1)
            tableHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(importer.items.filter { $0.state != .done }) { item in importRow(item) }
                    ForEach(rows) { note in noteRow(note) }
                }
            }
            if rows.isEmpty && importer.items.allSatisfy({ $0.state == .done }) {
                VStack(spacing: 6) {
                    Text("Nothing in the queue").font(MurmurTheme.Mac.bodyBold).foregroundStyle(MurmurTheme.Colors.textSecondary)
                    Text("Drop audio or video files on the window to transcribe them in a row.")
                        .font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MurmurTheme.Colors.background)
    }

    private func totalsText(_ stats: QueueStats) -> String {
        var parts = ["\(stats.done) done"]
        let open = stats.waiting + stats.working
        if open > 0 { parts.append("\(open) to go") }
        if let left = stats.secondsLeft, open > 0 { parts.append("about \(DurationText.remaining(left)) left") }
        return parts.joined(separator: " · ")
    }

    private var tableHeader: some View {
        HStack {
            Text("File").frame(maxWidth: .infinity, alignment: .leading)
            Text("Length").frame(width: 70, alignment: .trailing)
            Text("Progress").frame(width: 170, alignment: .leading).padding(.leading, 16)
            Text("Speed").frame(width: 110, alignment: .trailing)
        }
        .murmurSectionLabel()
        .padding(.horizontal, MurmurTheme.Mac.padding)
        .frame(height: 30)
        .background(MurmurTheme.Colors.panel)
    }

    private func importRow(_ item: ImportItem) -> some View {
        let fraction: Double? = { if case .converting(let value) = item.state { return value }; return nil }()
        let status: String = {
            switch item.state {
            case .waiting: "Waiting"
            case .converting(let value): "Preparing \(Int(value * 100))%"
            case .done: "Done"
            case .failed(let message): message
            }
        }()
        return row(name: item.displayName, length: item.duration, fraction: fraction, status: status, speed: "—", failed: { if case .failed = item.state { return true }; return false }())
    }

    private func noteRow(_ note: Note) -> some View {
        let current = queue.currentNoteID == note.id
        let fraction: Double? = note.status == .ready ? 1 : (current ? queue.fraction : nil)
        let status: String = {
            switch note.status {
            case .ready: "Done"
            case .transcribing: "\(Int(queue.fraction * 100))%"
            case .queued: "Waiting"
            case .failed: "Failed"
            case .recording: "Recording"
            }
        }()
        return row(name: note.title, length: note.duration, fraction: fraction, status: status,
                   speed: current ? RealtimeFactor.text(queue.speedFactor) : "—", failed: note.status == .failed)
            .contextMenu {
                if note.status == .failed {
                    Button("Try again") { note.status = .queued; queue.start() }
                }
            }
    }

    private func row(name: String, length: TimeInterval?, fraction: Double?, status: String, speed: String, failed: Bool) -> some View {
        HStack {
            Text(name).font(MurmurTheme.Mac.body).foregroundStyle(MurmurTheme.Colors.textPrimary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(length.map(Timecode.format) ?? "—").font(MurmurTheme.Mac.small.monospacedDigit())
                .foregroundStyle(MurmurTheme.Colors.textSecondary).frame(width: 70, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MurmurTheme.Colors.raised)
                        Capsule().fill(failed ? MurmurTheme.Colors.record : MurmurTheme.Colors.accent)
                            .frame(width: proxy.size.width * (fraction ?? 0))
                    }
                }
                .frame(height: 5)
                Text(status).font(MurmurTheme.Mac.small)
                    .foregroundStyle(failed ? MurmurTheme.Colors.record : MurmurTheme.Colors.textTertiary)
            }
            .frame(width: 170).padding(.leading, 16)
            Text(speed).font(MurmurTheme.Mac.small).foregroundStyle(MurmurTheme.Colors.textSecondary)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, MurmurTheme.Mac.padding)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(MurmurTheme.Colors.border).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}
