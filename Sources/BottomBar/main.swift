import AppKit

// Register your bottom bar items here — just like adding menu bar extras.
let bar = BottomBarController(
    items: [
        AerospaceBarItem(),
        UptimeBarItem(),
        CpuBarItem(),
        MemoryBarItem(),
        DiskBarItem(),
        NetworkBarItem(),
        PRsBarItem(),
    ],
    rightItems: [
        FocusedAppBarItem(),
        LocationBarItem(),
        ClockBarItem(),
    ]
)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        bar.show()
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
