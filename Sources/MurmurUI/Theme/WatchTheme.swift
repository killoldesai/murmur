import SwiftUI

public extension MurmurTheme {
    /// Apple Watch: pure black background, 44 pt full-width capsule buttons, small type.
    enum Watch {
        public static let buttonHeight: CGFloat = 44
        public static let recordButtonSize: CGFloat = 92
        public static let cardRadius: CGFloat = 16
        public static let timer = Font.system(size: 38, weight: .light).monospacedDigit()
        public static let title = Font.system(size: 16, weight: .bold)
        public static let body = Font.system(size: 14)
        public static let caption = Font.system(size: 12)
        public static let captionBold = Font.system(size: 12, weight: .semibold)
    }
}
