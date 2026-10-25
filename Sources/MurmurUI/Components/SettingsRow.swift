import SwiftUI

/// Settings list row: icon, title, and either a value with a chevron or an accent toggle.
public struct SettingsRow: View {
    let systemImage: String
    let title: String
    let value: String?
    let isOn: Binding<Bool>?

    /// Row that shows a value (or nothing) and a chevron.
    public init(systemImage: String, title: String, value: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.value = value
        self.isOn = nil
    }

    /// Row with a toggle.
    public init(systemImage: String, title: String, isOn: Binding<Bool>) {
        self.systemImage = systemImage
        self.title = title
        self.value = nil
        self.isOn = isOn
    }

    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(MurmurTheme.Colors.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(title)
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)

            Spacer(minLength: 8)

            if let isOn {
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .tint(MurmurTheme.Colors.accent)
            } else {
                if let value {
                    Text(value)
                        .font(MurmurTheme.Fonts.body)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MurmurTheme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: MurmurTheme.Metrics.minTapTarget + 12)
        .contentShape(Rectangle())
    }
}
