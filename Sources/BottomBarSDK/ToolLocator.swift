import Foundation

/// Finds command-line tools for plugins.
///
/// Apps launched from Finder don't inherit the shell's `PATH`, so this checks
/// common install locations first, then falls back to asking a login shell.
public enum ToolLocator {
    /// Results are cached, including misses, so polling plugins don't spawn a shell repeatedly.
    private static var cache: [String: URL?] = [:]
    private static let lock = NSLock()

    private static let searchDirectories: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.local/bin",
            "/usr/bin",
        ]
    }()

    /// Returns the URL of an executable named `name`, or nil if it can't be found.
    /// Tools installed while the app is running are picked up after a restart.
    /// Absolute paths (and `~/` paths) are returned as-is if executable.
    public static func find(_ name: String) -> URL? {
        let fm = FileManager.default
        let expanded = (name as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return fm.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }

        lock.lock()
        if let cached = cache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var found = searchDirectories
            .map { "\($0)/\(name)" }
            .first { fm.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }

        if found == nil {
            found = lookupViaLoginShell(name)
        }

        lock.lock()
        cache[name] = found
        lock.unlock()
        return found
    }

    private static func lookupViaLoginShell(_ name: String) -> URL? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "command -v -- \"$1\"", "zsh", name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard proc.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              path.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}
