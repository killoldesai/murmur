import SwiftUI

/// Every shared component on one scrolling screen. Used as the app's root screen during
/// build step 0 and as a visual check in CI screenshots.
public struct ComponentGallery: View {
    @State private var chip = 0
    @State private var plan = 1
    @State private var hapticsOn = true
    @State private var deleteAudio = false
    @State private var playing = true
    @State private var progress = 0.38

    public init() {}

    public var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Murmur")
                        .font(MurmurTheme.Fonts.largeTitle)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .murmurEntrance(index: 0)

                    section("Buttons", index: 1) {
                        PrimaryButton("Start recording", systemImage: "mic.fill") {}
                        SecondaryButton("Import audio", systemImage: "square.and.arrow.down") {}
                    }

                    section("Chips", index: 2) {
                        HStack(spacing: 8) {
                            ForEach(Array(["All", "Transcripts", "Summaries"].enumerated()), id: \.offset) { i, title in
                                Chip(title, isSelected: chip == i) { chip = i }
                            }
                        }
                    }

                    section("Note cards", index: 3) {
                        NoteCard(
                            title: "Product sync, Q4 roadmap",
                            meta: "Today, 10:30 AM · 42:10",
                            snippet: "We agreed to ship the Mac beta before the holidays and move pricing to next sprint.",
                            tint: MurmurTheme.Colors.folder(0)
                        )
                        NoteCard(
                            title: "Biology 201, Lecture 8",
                            meta: "Yesterday · 1:12:04",
                            tint: MurmurTheme.Colors.folder(2)
                        )
                    }

                    section("Transcript rows", index: 4) {
                        TranscriptRow(speaker: "Speaker 1", speakerColor: MurmurTheme.Colors.folder(0), timestamp: "00:12",
                                      text: "Let's start with where we landed on the roadmap.")
                        TranscriptRow(speaker: "Speaker 2", speakerColor: MurmurTheme.Colors.folder(1), timestamp: "00:19",
                                      text: "Mac first, then the Watch companion. Pricing can wait.", state: .playing)
                        TranscriptRow(speaker: "Speaker 1", speakerColor: MurmurTheme.Colors.folder(0), timestamp: "00:31",
                                      text: "Agreed. I'll write that up.", state: .editing)
                    }

                    section("Playback", index: 5) {
                        PlaybackBar(progress: progress, elapsed: 16 * 60 + 2, total: 42 * 60 + 10,
                                    isPlaying: playing, onTogglePlay: { playing.toggle() })
                    }

                    section("Waveform and progress", index: 6) {
                        HStack(spacing: 24) {
                            TimelineView(.animation) { context in
                                let t = context.date.timeIntervalSinceReferenceDate
                                Waveform(levels: (0..<28).map { i in
                                    CGFloat(0.2 + 0.8 * abs(sin(t * 2.2 + Double(i) * 0.55)))
                                }, height: 56)
                            }
                            ProgressRing(progress: 0.62)
                                .frame(width: 64, height: 64)
                        }
                    }

                    section("Plans", index: 7) {
                        PlanCard(name: "Yearly", price: "$19.99", detail: "7-day free trial", badge: "BEST VALUE",
                                 isSelected: plan == 1) { plan = 1 }
                        PlanCard(name: "Lifetime", price: "$39.99", detail: "Pay once, yours forever",
                                 isSelected: plan == 2) { plan = 2 }
                        PlanCard(name: "Monthly", price: "$3.99", detail: "Cancel anytime",
                                 isSelected: plan == 3) { plan = 3 }
                    }

                    section("Settings", index: 8) {
                        VStack(spacing: 0) {
                            SettingsRow(systemImage: "globe", title: "Language", value: "Auto-detect")
                            Divider().overlay(MurmurTheme.Colors.border)
                            SettingsRow(systemImage: "iphone.radiowaves.left.and.right", title: "Haptics", isOn: $hapticsOn)
                            Divider().overlay(MurmurTheme.Colors.border)
                            SettingsRow(systemImage: "trash", title: "Delete audio after transcribing", isOn: $deleteAudio)
                        }
                        .murmurCard()
                    }
                }
                .padding(MurmurTheme.Metrics.screenPadding)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, index: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Metrics.spacingM) {
            Text(title).murmurSectionLabel()
            content()
        }
        .murmurEntrance(index: index)
    }
}

#Preview {
    ComponentGallery()
}
