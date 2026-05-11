import AppKit
import BottomBarSDK

/// Loads `.bundle` plugins from `~/.bottombar/plugins/` and watches
/// the directory for changes to support hot-reloading.
class PluginManager {
    static let pluginsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bottombar")
            .appendingPathComponent("plugins")
    }()

    private var loadedBundles: [String: Bundle] = [:]
    private var loadedPlugins: [String: BottomBarPlugin] = [:]
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?

    /// Called when plugins change. Provides the full current list of plugin items.
    var onPluginsChanged: (([BottomBarItem]) -> Void)?

    init() {
        ensurePluginsDirectory()
    }

    /// Performs initial scan and starts watching for changes.
    func start() {
        scanAndLoad()
        onPluginsChanged?(currentItems())
        watchDirectory()
    }

    /// Returns all currently loaded plugins wrapped as `BottomBarItem`.
    func currentItems() -> [BottomBarItem] {
        loadedPlugins.values.map { PluginItemAdapter(plugin: $0) }
    }

    // MARK: - Scanning

    private func scanAndLoad() {
        let fm = FileManager.default
        let dir = Self.pluginsDirectory

        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let bundlePaths = contents.filter { $0.pathExtension == "bundle" }
        var currentIds = Set<String>()

        for url in bundlePaths {
            if let plugin = loadBundle(at: url) {
                currentIds.insert(plugin.id)
            }
        }

        // Remove plugins whose bundles were deleted
        let removedIds = Set(loadedPlugins.keys).subtracting(currentIds)
        for id in removedIds {
            loadedBundles.removeValue(forKey: id)
            loadedPlugins.removeValue(forKey: id)
            NSLog("[PluginManager] Unloaded plugin: \(id)")
        }
    }

    @discardableResult
    private func loadBundle(at url: URL) -> BottomBarPlugin? {
        // If already loaded from this path, unload first for hot-reload
        let existingId = loadedBundles.first(where: {
            $0.value.bundlePath == url.path
        })?.key
        if let id = existingId {
            loadedBundles.removeValue(forKey: id)
            loadedPlugins.removeValue(forKey: id)
        }

        guard let bundle = Bundle(url: url) else {
            NSLog("[PluginManager] Failed to create bundle at \(url.path)")
            return nil
        }

        // For hot-reload: if already loaded, unload first
        if bundle.isLoaded {
            bundle.unload()
        }

        guard bundle.load() else {
            NSLog("[PluginManager] Failed to load bundle at \(url.path)")
            return nil
        }

        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            NSLog("[PluginManager] No principal class conforming to NSObject in \(url.lastPathComponent)")
            return nil
        }

        let instance = principalClass.init()

        guard let plugin = instance as? BottomBarPlugin else {
            NSLog("[PluginManager] Principal class does not conform to BottomBarPlugin in \(url.lastPathComponent)")
            return nil
        }

        loadedBundles[plugin.id] = bundle
        loadedPlugins[plugin.id] = plugin
        NSLog("[PluginManager] Loaded plugin: \(plugin.id) from \(url.lastPathComponent)")
        return plugin
    }

    // MARK: - Directory Watching

    private func watchDirectory() {
        let path = Self.pluginsDirectory.path
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            NSLog("[PluginManager] Failed to open plugins directory for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            NSLog("[PluginManager] Plugins directory changed, reloading...")
            self.scanAndLoad()
            self.onPluginsChanged?(self.currentItems())
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        source.resume()
        dispatchSource = source
    }

    // MARK: - Helpers

    private func ensurePluginsDirectory() {
        let fm = FileManager.default
        let dir = Self.pluginsDirectory
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            NSLog("[PluginManager] Created plugins directory at \(dir.path)")
        }
    }

    deinit {
        dispatchSource?.cancel()
    }
}
