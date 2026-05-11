import SwiftUI

/// The interface for adding apps to the bottom bar.
///
/// Conform to this protocol to create a bottom bar item — similar to how
/// `NSStatusItem` works for the macOS top menu bar.
///
/// By default, items show as an icon+title button that opens a popover panel.
/// Override `makeBarView()` to provide a custom inline view in the bar itself
/// (e.g. for always-visible content like clocks). Items with a custom bar view
/// can still have a popover if `panelSize` is non-zero.
protocol BottomBarItem {
    /// Unique identifier for this item.
    var id: String { get }

    /// Title shown in the bar button. Ignored if `makeBarView` is provided.
    var title: String { get }

    /// SF Symbol name for the bar icon. Ignored if `makeBarView` is provided.
    var icon: String { get }

    /// Size of the popover panel. Return `.zero` for no popover.
    var panelSize: CGSize { get }

    /// Build the SwiftUI content displayed in the popover panel.
    /// Call `close` to dismiss the panel programmatically.
    func makeContent(close: @escaping () -> Void) -> AnyView

    /// Which side of the bar: "left" or "right". Defaults to "left".
    var side: String { get }

    /// Optional: provide a custom inline view for the bar itself.
    /// When nil, the default icon+title button is used.
    func makeBarView() -> AnyView?
}

extension BottomBarItem {
    func makeBarView() -> AnyView? { nil }
    var side: String { "left" }
}
