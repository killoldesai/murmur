import SwiftUI
import MurmurCore
import MurmurUI

// These views are compiled into both the watch app (for screenshots) and the widget extension.

/// Circular complication: the waveform icon, or today's note count.
struct WatchCircularView: View {
    let snapshot: WatchSnapshot
    var showsCount = true

    var body: some View {
        ZStack {
            Circle().strokeBorder(MurmurTheme.Colors.accent, lineWidth: 3)
            if showsCount && snapshot.notesToday > 0 {
                VStack(spacing: -2) {
                    Text("\(snapshot.notesToday)").font(.system(size: 22, weight: .bold)).foregroundStyle(MurmurTheme.Colors.textPrimary)
                    Text("NOTES").font(.system(size: 8, weight: .bold)).foregroundStyle(MurmurTheme.Colors.accent)
                }
            } else {
                Image(systemName: "waveform").font(.system(size: 20, weight: .bold)).foregroundStyle(MurmurTheme.Colors.accent)
            }
        }
        .accessibilityLabel(snapshot.notesToday > 0 ? "\(snapshot.notesToday) notes today" : "Record with Murmur")
    }
}

/// Rectangular complication: tap to record, last memo status.
struct WatchRectangularView: View {
    let snapshot: WatchSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MURMUR").font(.system(size: 11, weight: .bold)).foregroundStyle(MurmurTheme.Colors.accent)
            Text("Tap to record").font(.system(size: 15, weight: .semibold)).foregroundStyle(MurmurTheme.Colors.textPrimary)
            Text(snapshot.lastMemoText).font(.system(size: 11)).foregroundStyle(MurmurTheme.Colors.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Smart Stack card: a record button and the two latest memos.
struct WatchSmartStackView: View {
    let snapshot: WatchSnapshot

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(MurmurTheme.Colors.record)
                Image(systemName: "mic.fill").foregroundStyle(.white).font(.system(size: 18))
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                if snapshot.recent.isEmpty {
                    Text("No memos yet").font(.system(size: 13)).foregroundStyle(MurmurTheme.Colors.textSecondary)
                }
                ForEach(Array(snapshot.recent.enumerated()), id: \.offset) { _, memo in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(memo.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(MurmurTheme.Colors.textPrimary)
                        Text(memo.detail).font(.system(size: 10)).foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The complications screenshot: all three, on black.
struct WatchComplicationsPreview: View {
    let snapshot: WatchSnapshot

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchCircularView(snapshot: snapshot).frame(width: 58, height: 58)
                WatchRectangularView(snapshot: snapshot)
                    .padding(10).background(RoundedRectangle(cornerRadius: 14).fill(MurmurTheme.Colors.surface))
                WatchSmartStackView(snapshot: snapshot)
                    .padding(10).background(RoundedRectangle(cornerRadius: 14).fill(MurmurTheme.Colors.surface))
            }
        }
    }
}
