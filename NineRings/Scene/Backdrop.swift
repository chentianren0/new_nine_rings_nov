import CoreGraphics
import SwiftUI

/// The plain background behind the toy, in light and dark appearance.
enum Backdrop {
    enum Appearance: String {
        case light, dark

        init(_ scheme: ColorScheme) {
            self = scheme == .dark ? .dark : .light
        }

        var backgroundColor: CGColor {
            switch self {
            case .light: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            case .dark: CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            }
        }
    }

    static func color(for scheme: ColorScheme) -> Color {
        Color(cgColor: Appearance(scheme).backgroundColor)
    }
}
