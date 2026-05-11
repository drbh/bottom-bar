import AppKit
import SwiftUI
import BottomBarSDK

class FocusedAppBarPlugin: NSObject, BottomBarPlugin {
    let id = "focused-app"
    let title = ""
    let icon = ""
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: FocusedAppInlineView())
    }
}

private class FocusedAppModel: ObservableObject {
    @Published var appName: String = ""
    private var observer: NSObjectProtocol?

    init() {
        updateFocusedApp()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.appName = app.localizedName ?? ""
            }
        }
    }

    private func updateFocusedApp() {
        appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }

    deinit {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

private struct FocusedAppInlineView: View {
    @StateObject private var model = FocusedAppModel()

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "macwindow")
                .font(BarFont.regular(10))
                .foregroundColor(.secondary)
            Text(model.appName)
                .font(BarFont.regular(12))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
    }
}
