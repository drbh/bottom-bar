import SwiftUI

/// Shared font configuration for the bottom bar.
/// Change the family here to update all bar items at once.
public enum BarFont {
    public static let family = "IoskeleyMonoTermNF"

    public static func regular(_ size: CGFloat) -> Font {
        .custom(family, size: size)
    }

    public static func medium(_ size: CGFloat) -> Font {
        .custom("\(family)-Medium", size: size)
    }

    public static func bold(_ size: CGFloat) -> Font {
        .custom("\(family)-Bold", size: size)
    }

    public static func light(_ size: CGFloat) -> Font {
        .custom("\(family)-Light", size: size)
    }
}
