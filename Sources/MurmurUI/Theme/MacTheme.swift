import SwiftUI

public extension MurmurTheme {
    /// Mac density: 13 pt body, 30 pt controls with 8 pt radius, 30 pt sidebar rows with 7 pt radius.
    enum Mac {
        public static let controlHeight: CGFloat = 30
        public static let controlRadius: CGFloat = 8
        public static let rowHeight: CGFloat = 30
        public static let rowRadius: CGFloat = 7
        public static let headerHeight: CGFloat = 52
        /// Room for the window's traffic-light buttons at the left of the header.
        public static let trafficLightsInset: CGFloat = 78
        public static let sidebarWidth: CGFloat = 220
        public static let listWidth: CGFloat = 300
        public static let inspectorWidth: CGFloat = 280
        public static let padding: CGFloat = 16

        public static let body = Font.system(size: 13)
        public static let bodyBold = Font.system(size: 13, weight: .semibold)
        public static let small = Font.system(size: 11)
        public static let smallBold = Font.system(size: 11, weight: .bold)
        public static let title = Font.system(size: 20, weight: .bold)
        public static let timer = Font.system(size: 34, weight: .light).monospacedDigit()
    }
}
