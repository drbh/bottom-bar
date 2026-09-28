import AppKit
import SwiftUI
import BottomBarSDK

/// Example plugin that displays "Hello" in the bar.
/// Use this as a template for creating your own plugins.
///
/// To build:
///   cd ExamplePlugin && swift build
///
/// To install:
///   cp -r .build/debug/libHelloPlugin.dylib ~/.bottombar/plugins/HelloPlugin.bundle/Contents/MacOS/
///
/// Or use the build-plugin.sh script included in this directory.
class HelloBarPlugin: NSObject, BottomBarPlugin {
    let id = "hello-plugin"
    let title = "Hello"
    let icon = "hand.wave"
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    func makeContentView(close: @escaping () -> Void) -> NSView {
        NSView()
    }

    func makeBarNSView() -> NSView? {
        let view = NSHostingView(rootView: HelloInlineView())
        return view
    }
}

private struct HelloInlineView: View {
    @State private var greeting = "Hello!"

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "hand.wave")
                .font(BarFont.medium(10))
                .foregroundColor(.secondary)
            Text(greeting)
                .font(BarFont.regular(12))
        }
        .padding(.horizontal, 6)
    }
}
