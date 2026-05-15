import AppKit

// Plugin manager — loads .bundle plugins from ~/.bottombar/plugins/
let pluginManager = PluginManager()

// Create one BottomBarController per bar defined in config, stacking upward.
let coordinator = BarCoordinator()
var bars: [BottomBarController] = []

for i in 0..<max(pluginManager.barCount, 1) {
    let yOffset = CGFloat(i) * BottomBarController.barHeight
    let controller = BottomBarController(
        items: pluginManager.itemsForBar(i),
        yOffset: yOffset
    )
    let barConf = pluginManager.configForBar(i)
    controller.backgroundSetting = barConf?.background
    controller.passthrough = barConf?.passthrough ?? false
    controller.borderColorSetting = barConf?.borderColor
    controller.coordinator = coordinator
    coordinator.register(controller)
    bars.append(controller)
}

// Hot-reload: when plugins or config change, rebuild all bars.
pluginManager.onPluginsChanged = { _ in
    // Resize bars array if config changed the bar count
    let count = max(pluginManager.barCount, 1)
    while bars.count < count {
        let i = bars.count
        let yOffset = CGFloat(i) * BottomBarController.barHeight
        let controller = BottomBarController(
            items: pluginManager.itemsForBar(i),
            yOffset: yOffset
        )
        controller.backgroundSetting = pluginManager.configForBar(i)?.background
        controller.coordinator = coordinator
        coordinator.register(controller)
        bars.append(controller)
        controller.show()
    }
    for (i, controller) in bars.prefix(count).enumerated() {
        let barConf = pluginManager.configForBar(i)
        controller.backgroundSetting = barConf?.background
        controller.passthrough = barConf?.passthrough ?? false
        controller.borderColorSetting = barConf?.borderColor
        controller.replacePluginItems(pluginManager.itemsForBar(i))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        for controller in bars {
            controller.show()
        }
        pluginManager.start()
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
