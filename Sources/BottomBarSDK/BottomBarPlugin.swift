import AppKit
import SwiftUI

/// The interface for hot-loadable bottom bar plugins.
///
/// Plugins are compiled as `.bundle` files and placed in
/// `~/.bottombar/plugins/`. The host app loads them at runtime
/// via `NSBundle` and calls these methods to render bar content.
///
/// Because SwiftUI types can't cross bundle boundaries, this
/// protocol uses `NSView` as the bridge type. Wrap your SwiftUI
/// views with `NSHostingView` before returning them.
@objc public protocol BottomBarPlugin: NSObjectProtocol {
    /// Unique identifier for this plugin.
    var id: String { get }

    /// Title shown in the default bar button. Ignored if `makeBarNSView` is provided.
    var title: String { get }

    /// SF Symbol name for the bar icon. Ignored if `makeBarNSView` is provided.
    var icon: String { get }

    /// Width of the popover panel. Return 0 for no popover.
    var panelWidth: CGFloat { get }

    /// Height of the popover panel. Return 0 for no popover.
    var panelHeight: CGFloat { get }

    /// Build the content displayed in the popover panel.
    /// Call `close` to dismiss the panel programmatically.
    /// Wrap SwiftUI views with `NSHostingView`.
    func makeContentView(close: @escaping () -> Void) -> NSView

    /// Optional: provide a custom inline view for the bar itself.
    /// When nil, the default icon+title button is used.
    /// Wrap SwiftUI views with `NSHostingView`.
    @objc optional func makeBarNSView() -> NSView?

    /// Optional: receive per-instance configuration from config.jsonc.
    /// Called before `makeBarNSView` / `makeContentView`.
    /// The dictionary contains whatever the user put in the `"config"` key.
    @objc optional func setConfiguration(_ config: [String: Any])
}
