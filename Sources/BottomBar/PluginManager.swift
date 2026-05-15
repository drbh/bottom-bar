import AppKit
import BottomBarSDK

// MARK: - Config Model

/// Represents a single bar definition inside `~/.bottombar/config.jsonc`.
struct BarConfig: Codable {
    /// Ordered list of plugin IDs for the left side.
    var left: [String]?
    /// Ordered list of plugin IDs for the right side.
    var right: [String]?
    /// Background color: hex string (e.g. "#1a1a2e") or "none" for transparent.
    var background: String?
    /// Whether clicks on empty bar areas pass through to windows below (e.g. the Dock).
    var passthrough: Bool?
    /// Top border color: hex string (e.g. "#ffffff") or "none" to hide.
    var borderColor: String?

    var allIds: [String] {
        (left ?? []) + (right ?? [])
    }
}

/// Represents `~/.bottombar/config.jsonc`.
/// Supports both the legacy single-bar format (`left`/`right` at top level)
/// and the new multi-bar format (`bars` array).
struct BottomBarConfig: Codable {
    /// Legacy single-bar keys (kept for backwards compat).
    var left: [String]?
    var right: [String]?
    /// Multi-bar definitions — first bar is at the bottom, subsequent bars stack above.
    var bars: [BarConfig]?

    /// Resolved list of bar configs. Falls back to legacy format when `bars` is nil.
    var resolvedBars: [BarConfig] {
        if let bars = bars, !bars.isEmpty {
            return bars
        }
        // Legacy: single bar from top-level left/right
        return [BarConfig(left: left, right: right)]
    }

    /// All enabled IDs across all bars.
    var allIds: [String] {
        resolvedBars.flatMap { $0.allIds }
    }

    static let defaultConfig = BottomBarConfig(left: nil, right: nil, bars: nil)
}

/// Loads `.bundle` plugins from `~/.bottombar/plugins/` and watches
/// the directory and config file for changes to support hot-reloading.
class PluginManager {
    static let baseDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bottombar")
    }()

    static let pluginsDirectory: URL = {
        baseDirectory.appendingPathComponent("plugins")
    }()

    static let configFile: URL = {
        baseDirectory.appendingPathComponent("config.jsonc")
    }()

    private var loadedBundles: [String: Bundle] = [:]
    private var loadedPlugins: [String: BottomBarPlugin] = [:]
    private var config: BottomBarConfig = .defaultConfig
    private var pluginsDirFD: Int32 = -1
    private var configFD: Int32 = -1
    private var pluginsDirSource: DispatchSourceFileSystemObject?
    private var configSource: DispatchSourceFileSystemObject?

    /// Called when plugins or config change.
    var onPluginsChanged: (([BottomBarItem]) -> Void)?

    init() {
        ensurePluginsDirectory()
        ensureConfigFile()
    }

    /// Performs initial scan and starts watching for changes.
    func start() {
        loadConfig()
        scanAndLoad()
        onPluginsChanged?(currentItems())
        watchPluginsDirectory()
        watchConfigFile()
    }

    /// Number of bars defined in the current config.
    var barCount: Int {
        config.resolvedBars.count
    }

    /// Returns the BarConfig for a given bar index.
    func configForBar(_ index: Int) -> BarConfig? {
        let bars = config.resolvedBars
        guard index < bars.count else { return nil }
        return bars[index]
    }

    /// Returns enabled plugins for a specific bar index, in config order.
    func itemsForBar(_ index: Int) -> [BottomBarItem] {
        let bars = config.resolvedBars
        guard index < bars.count else { return [] }
        let barConfig = bars[index]

        guard barConfig.left != nil || barConfig.right != nil else {
            // No config — show all plugins on bar 0 only
            if index == 0 {
                return loadedPlugins.values.map { PluginItemAdapter(plugin: $0) }
            }
            return []
        }

        var items: [BottomBarItem] = []

        for id in barConfig.left ?? [] {
            if let plugin = loadedPlugins[id] {
                items.append(PluginItemAdapter(plugin: plugin, sideOverride: "left"))
            }
        }

        for id in barConfig.right ?? [] {
            if let plugin = loadedPlugins[id] {
                items.append(PluginItemAdapter(plugin: plugin, sideOverride: "right"))
            }
        }

        return items
    }

    /// Returns enabled plugins for the first (bottom) bar. Legacy convenience.
    func currentItems() -> [BottomBarItem] {
        itemsForBar(0)
    }

    // MARK: - Config

    private func loadConfig() {
        let url = Self.configFile
        guard FileManager.default.fileExists(atPath: url.path),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            config = .defaultConfig
            return
        }

        let stripped = Self.stripJSONComments(raw)
        guard let data = stripped.data(using: .utf8) else {
            config = .defaultConfig
            return
        }

        do {
            config = try JSONDecoder().decode(BottomBarConfig.self, from: data)
            let summary = "left: \(config.left?.joined(separator: ", ") ?? "all"), right: \(config.right?.joined(separator: ", ") ?? "none")"
            NSLog("[PluginManager] Config loaded: \(summary)")
        } catch {
            NSLog("[PluginManager] Failed to parse config.jsonc: \(error.localizedDescription)")
            config = .defaultConfig
        }
    }

    /// Strip `//` and `/* */` comments from JSONC text.
    private static func stripJSONComments(_ input: String) -> String {
        var result = ""
        var i = input.startIndex
        let end = input.endIndex
        var inString = false
        var escaped = false

        while i < end {
            let c = input[i]

            if inString {
                result.append(c)
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
                i = input.index(after: i)
                continue
            }

            if c == "\"" {
                inString = true
                result.append(c)
                i = input.index(after: i)
                continue
            }

            let next = input.index(after: i)
            if c == "/" && next < end {
                let c2 = input[next]
                if c2 == "/" {
                    // Line comment — skip to end of line
                    var j = input.index(after: next)
                    while j < end && input[j] != "\n" { j = input.index(after: j) }
                    i = j
                    continue
                } else if c2 == "*" {
                    // Block comment — skip to */
                    var j = input.index(after: next)
                    while j < end {
                        let jNext = input.index(after: j)
                        if input[j] == "*" && jNext < end && input[jNext] == "/" {
                            i = input.index(after: jNext)
                            break
                        }
                        j = input.index(after: j)
                    }
                    if j >= end { i = end }
                    continue
                }
            }

            result.append(c)
            i = input.index(after: i)
        }

        return result
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

    // MARK: - Watching

    private func watchPluginsDirectory() {
        let path = Self.pluginsDirectory.path
        pluginsDirFD = open(path, O_EVTONLY)
        guard pluginsDirFD >= 0 else {
            NSLog("[PluginManager] Failed to open plugins directory for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: pluginsDirFD,
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
            if self.pluginsDirFD >= 0 {
                close(self.pluginsDirFD)
                self.pluginsDirFD = -1
            }
        }

        source.resume()
        pluginsDirSource = source
    }

    private func watchConfigFile() {
        let path = Self.configFile.path
        configFD = open(path, O_EVTONLY)
        guard configFD >= 0 else {
            NSLog("[PluginManager] Failed to open config file for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: configFD,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            NSLog("[PluginManager] Config changed, reloading...")
            self.loadConfig()
            self.onPluginsChanged?(self.currentItems())
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.configFD >= 0 {
                close(self.configFD)
                self.configFD = -1
            }
        }

        source.resume()
        configSource = source
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

    private func ensureConfigFile() {
        let fm = FileManager.default
        let url = Self.configFile
        if !fm.fileExists(atPath: url.path) {
            let defaultContent = """
            {
              // Each entry in "bars" defines a bar. The first bar sits at the
              // bottom of the screen; subsequent bars stack above it.
              "bars": [
                {
                  // Bottom bar
                  "left": [
                    "aerospace",
                    "uptime",
                    "cpu",
                    "memory",
                    "disk",
                    "network",
                    "prs"
                  ],
                  "right": [
                    "focused-app",
                    "location",
                    "clock"
                  ]
                }
                // Uncomment to add a second bar above the first:
                // ,{
                //   "left": ["my-plugin"],
                //   "right": ["another-plugin"]
                // }
              ]
            }
            """
            try? defaultContent.write(to: url, atomically: true, encoding: .utf8)
            NSLog("[PluginManager] Created default config at \(url.path)")
        }
    }

    deinit {
        pluginsDirSource?.cancel()
        configSource?.cancel()
    }
}

private extension JSONEncoder {
    static let prettyPrinting: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
