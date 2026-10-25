import SwiftUI

public extension Color {
    /// `Color(hex: 0x5EE0C6)` in sRGB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Single source of truth for every colour, size and font in the app.
/// Screens must never hard-code values; add a token here instead.
/// Style is solid and flat: no gradients, glows, blur or glass.
public enum MurmurTheme {

    /// Raw hex values (kept separate so tests and non-SwiftUI code can read them).
    public enum Palette {
        public static let background: UInt32 = 0x111116
        public static let surface: UInt32 = 0x1C1C23
        public static let panel: UInt32 = 0x16161C
        public static let raised: UInt32 = 0x26262E
        public static let border: UInt32 = 0x2A2A33
        public static let accent: UInt32 = 0x5EE0C6
        public static let onAccent: UInt32 = 0x06231E
        public static let selectedFill: UInt32 = 0x16302B
        public static let record: UInt32 = 0xFF5A6E
        public static let textPrimary: UInt32 = 0xF4F3F8
        public static let textSecondary: UInt32 = 0xB9B7C8
        public static let textTertiary: UInt32 = 0x8F8D9C
        /// Pure black for the Apple Watch OLED background.
        public static let watchBackground: UInt32 = 0x000000
        /// Folder, note-tile and speaker colours, in order.
        public static let folders: [UInt32] = [0x5EE0C6, 0xFFB86B, 0xA9B4FF, 0xFF8FA3, 0x8FD3FF]
    }

    public enum Colors {
        public static let background = Color(hex: Palette.background)
        public static let surface = Color(hex: Palette.surface)
        public static let panel = Color(hex: Palette.panel)
        public static let raised = Color(hex: Palette.raised)
        public static let border = Color(hex: Palette.border)
        public static let accent = Color(hex: Palette.accent)
        public static let onAccent = Color(hex: Palette.onAccent)
        public static let selectedFill = Color(hex: Palette.selectedFill)
        public static let record = Color(hex: Palette.record)
        public static let textPrimary = Color(hex: Palette.textPrimary)
        public static let textSecondary = Color(hex: Palette.textSecondary)
        public static let textTertiary = Color(hex: Palette.textTertiary)
        public static let watchBackground = Color(hex: Palette.watchBackground)

        /// Wraps around, so any index is safe (e.g. speaker 7 reuses colour 2).
        public static func folder(_ index: Int) -> Color {
            let list = Palette.folders
            let i = ((index % list.count) + list.count) % list.count
            return Color(hex: list[i])
        }
    }

    public enum Metrics {
        public static let cardRadius: CGFloat = 20       // spec: 18-22
        public static let buttonHeight: CGFloat = 56
        public static let buttonRadius: CGFloat = 18
        public static let minTapTarget: CGFloat = 44
        public static let screenPadding: CGFloat = 20
        public static let borderWidth: CGFloat = 1
        public static let selectedBorderWidth: CGFloat = 1.5
        public static let spacingS: CGFloat = 8
        public static let spacingM: CGFloat = 12
        public static let spacingL: CGFloat = 20
    }

    /// Text styles map to Dynamic Type styles so they scale with the user's setting.
    public enum Fonts {
        public static let largeTitle = Font.largeTitle.weight(.heavy)   // 34 pt
        public static let title = Font.title.weight(.heavy)             // 28 pt
        public static let headline = Font.headline.weight(.bold)        // 17 pt
        public static let body = Font.callout                           // 16 pt
        public static let caption = Font.caption                        // 12 pt
        public static let sectionLabel = Font.caption.weight(.bold)     // use with .murmurSectionLabel()
        /// Timers use monospaced digits so they don't jitter.
        public static let timer = Font.system(size: 56, weight: .light).monospacedDigit()
    }
}

public extension View {
    /// 12 pt bold uppercase label with wide tracking.
    func murmurSectionLabel() -> some View {
        self.font(MurmurTheme.Fonts.sectionLabel)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(MurmurTheme.Colors.textTertiary)
    }

    /// Standard card: surface fill, 1 pt border, card radius.
    func murmurCard(selected: Bool = false) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: MurmurTheme.Metrics.cardRadius, style: .continuous)
                .fill(selected ? MurmurTheme.Colors.selectedFill : MurmurTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MurmurTheme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(
                    selected ? MurmurTheme.Colors.accent : MurmurTheme.Colors.border,
                    lineWidth: selected ? MurmurTheme.Metrics.selectedBorderWidth : MurmurTheme.Metrics.borderWidth
                )
        )
    }
}
