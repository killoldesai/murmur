import WidgetKit
import SwiftUI
import MurmurCore
import MurmurUI

struct MemoEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot
}

struct MemoProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemoEntry {
        MemoEntry(date: Date(), snapshot: WatchSnapshot(notesToday: 3, waitingCount: 0, lastMemoText: "Last memo 0:58 · sent to iphone", recent: []))
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoEntry) -> Void) {
        completion(MemoEntry(date: Date(), snapshot: WatchSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoEntry>) -> Void) {
        // The watch app reloads timelines whenever a recording changes; refresh hourly regardless
        // so "notes today" rolls over at midnight.
        let entry = MemoEntry(date: Date(), snapshot: WatchSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

/// Circular, corner and inline complications. Tapping opens Murmur and starts recording.
struct RecordComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MurmurRecord", provider: MemoProvider()) { entry in
            WatchCircularView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "murmur://record"))
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Record")
        .description("Tap to record a memo. Shows how many notes you made today.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// Rectangular complication and Smart Stack card.
struct MemosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MurmurMemos", provider: MemoProvider()) { entry in
            WatchRectangularView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "murmur://record"))
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Memos")
        .description("Tap to record. Shows the status of your last memo.")
        .supportedFamilies([.accessoryRectangular])
    }
}

/// Smart Stack card: a record button and the two latest memos.
struct SmartStackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MurmurSmartStack", provider: MemoProvider()) { entry in
            WatchSmartStackView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "murmur://record"))
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Recent memos")
        .description("A record button and your two latest memos.")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct MurmurWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordComplication()
        MemosWidget()
        SmartStackWidget()
    }
}
