import SwiftUI

/// Shared font configuration for the bottom bar.
/// Change the family here to update all bar items at once.
enum BarFont {
    static let family = "IoskeleyMonoTermNF"

    static func regular(_ size: CGFloat) -> Font {
        .custom(family, size: size)
    }

    static func medium(_ size: CGFloat) -> Font {
        .custom("\(family)-Medium", size: size)
    }

    static func bold(_ size: CGFloat) -> Font {
        .custom("\(family)-Bold", size: size)
    }

    static func light(_ size: CGFloat) -> Font {
        .custom("\(family)-Light", size: size)
    }
}
