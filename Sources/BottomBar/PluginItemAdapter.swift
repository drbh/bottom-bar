import AppKit
import SwiftUI
import BottomBarSDK

/// Bridges a `BottomBarPlugin` (NSView-based, loaded from a bundle) into
/// a `BottomBarItem` (AnyView-based, used by the host bar).
struct PluginItemAdapter: BottomBarItem {
    let plugin: BottomBarPlugin

    var id: String { plugin.id }
    var title: String { plugin.title }
    var icon: String { plugin.icon }
    var side: String { plugin.side ?? "left" }

    var panelSize: CGSize {
        let w = plugin.panelWidth
        let h = plugin.panelHeight
        guard w > 0, h > 0 else { return .zero }
        return CGSize(width: w, height: h)
    }

    func makeContent(close: @escaping () -> Void) -> AnyView {
        let nsView = plugin.makeContentView(close: close)
        return AnyView(NSViewWrapper(nsView: nsView))
    }

    func makeBarView() -> AnyView? {
        guard let nsView = plugin.makeBarNSView?() else { return nil }
        return AnyView(NSViewWrapper(nsView: nsView).fixedSize())
    }
}

/// Wraps an `NSView` (typically `NSHostingView`) for use in SwiftUI,
/// respecting its intrinsic content size.
private struct NSViewWrapper: NSViewRepresentable {
    let nsView: NSView

    func makeNSView(context: Context) -> NSView {
        // Ensure the hosting view sizes to fit its content
        nsView.setContentHuggingPriority(.required, for: .horizontal)
        nsView.setContentHuggingPriority(.required, for: .vertical)
        nsView.setContentCompressionResistancePriority(.required, for: .horizontal)
        nsView.setContentCompressionResistancePriority(.required, for: .vertical)
        return nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
