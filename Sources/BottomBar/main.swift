import AppKit

// Plugin manager — loads .bundle plugins from ~/.bottombar/plugins/
let pluginManager = PluginManager()

let bar = BottomBarController(
    items: pluginManager.currentItems()
)

// Hot-reload: when plugins change, update the bar
pluginManager.onPluginsChanged = { pluginItems in
    bar.replacePluginItems(pluginItems)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        bar.show()
        pluginManager.start()
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
