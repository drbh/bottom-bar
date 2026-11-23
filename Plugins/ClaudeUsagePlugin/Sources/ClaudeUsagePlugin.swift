import AppKit
import Combine
import SwiftUI
import BottomBarSDK

/// Shows Claude plan usage (session / weekly limits) as reported by the same
/// endpoint Claude Code's `/usage` uses. Reads the OAuth token Claude Code
/// stores in the macOS Keychain on every poll, so token refreshes done by the
/// CLI are picked up automatically.
///
/// Note: the endpoint is undocumented and may change.
class ClaudeUsageBarPlugin: NSObject, BottomBarPlugin {
    let id = "claude-usage"
    let title = ""
    let icon = ""
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    private var interval: TimeInterval = 120
    private var showWeekly = true
    private var showReset = true
    private var colorize = true

    func setConfiguration(_ config: [String: Any]) {
        if let n = config["interval"] as? Double { interval = max(30, n) }
        if let n = config["interval"] as? Int { interval = max(30, Double(n)) }
        if let b = config["showWeekly"] as? Bool { showWeekly = b }
        if let b = config["showReset"] as? Bool { showReset = b }
        if let b = config["color"] as? Bool { colorize = b }
    }

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: ClaudeUsageInlineView(
            model: UsageModel(interval: interval),
            showWeekly: showWeekly,
            showReset: showReset,
            colorize: colorize
        ))
    }
}

// MARK: - Model

private struct UsageLimit {
    let kind: String
    let label: String
    let percent: Double
    let severity: String
    let resetsAt: Date?
}

private enum UsageError: Error {
    case noToken, unauthorized, http(Int), parse
}

private class UsageModel: ObservableObject {
    @Published var limits: [UsageLimit] = []
    @Published var error: String? = nil
    @Published var lastUpdated: Date? = nil
    /// Set while the endpoint has told us to back off (HTTP 429 + Retry-After).
    @Published var blockedUntil: Date? = nil
    private var timer: Timer?
    private var consecutive429 = 0

    private let cache = DiskCache(name: "claude-usage")

    init(interval: TimeInterval) {
        // Show the last known values immediately so restarts don't flash "…".
        var age = TimeInterval.infinity
        if let (data, savedAt) = cache.load(), let limits = Self.parse(data) {
            self.limits = limits
            self.lastUpdated = savedAt
            age = Date().timeIntervalSince(savedAt)
        }

        // Respect a back-off from a previous run, and skip the startup request if
        // the cached copy is still fresh — restarts shouldn't burn rate limit.
        if let until = cache.loadBlockedUntil(), until > Date() {
            scheduleRetry(at: until)
        } else if age < interval {
            DispatchQueue.main.asyncAfter(deadline: .now() + (interval - age)) { [weak self] in self?.fetch() }
        } else {
            fetch()
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    private func scheduleRetry(at until: Date) {
        blockedUntil = until
        DispatchQueue.main.asyncAfter(deadline: .now() + until.timeIntervalSinceNow + 1) { [weak self] in
            self?.blockedUntil = nil
            self?.fetch()
        }
    }

    deinit { timer?.invalidate() }

    func fetch() {
        if let until = blockedUntil, until > Date() { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let token = Self.readToken() else {
                DispatchQueue.main.async { self?.error = "no login" }
                return
            }
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.timeoutInterval = 15

            URLSession.shared.dataTask(with: req) { data, resp, err in
                let result: Result<[UsageLimit], UsageError>
                var retryAfter: TimeInterval? = nil
                if let http = resp as? HTTPURLResponse, http.statusCode == 429 {
                    retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init) ?? 120
                    result = .failure(.http(429))
                } else if let http = resp as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
                    result = .failure(.unauthorized)
                } else if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    result = .failure(.http(http.statusCode))
                } else if let data, err == nil, let limits = Self.parse(data) {
                    result = .success(limits)
                    self?.cache.save(data)
                } else {
                    result = .failure(.parse)
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let retryAfter {
                        // Back off as instructed, then try once more; the regular timer resumes after.
                        // Exponential back-off on repeated 429s (60s, 120s, 240s… up to 15m);
                        // the server's Retry-After is often 0 while still limiting.
                        self.consecutive429 += 1
                        let backoff = 60 * pow(2, Double(self.consecutive429 - 1))
                        let until = Date().addingTimeInterval(min(max(retryAfter, backoff), 900))
                        self.cache.saveBlockedUntil(until)
                        self.scheduleRetry(at: until)
                        return
                    }
                    self.blockedUntil = nil
                    switch result {
                    case .success(let limits):
                        self.consecutive429 = 0
                        self.limits = limits
                        self.error = nil
                        self.lastUpdated = Date()
                    case .failure(.unauthorized):
                        // Token expired; Claude Code refreshes it next time it runs.
                        self.error = "stale"
                    case .failure(.http(let code)):
                        // Keep last-known values on transient errors (e.g. 429).
                        if self.limits.isEmpty { self.error = "http \(code)" }
                    case .failure:
                        if self.limits.isEmpty { self.error = "err" }
                    }
                }
            }.resume()
        }
    }

    /// Reads Claude Code's OAuth access token from the login Keychain via `security`.
    private static func readToken() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func parse(_ data: Data) -> [UsageLimit]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Preferred: the `limits` array (what /usage renders).
        if let arr = json["limits"] as? [[String: Any]], !arr.isEmpty {
            return arr.compactMap { item in
                guard let kind = item["kind"] as? String,
                      let pct = (item["percent"] as? NSNumber)?.doubleValue else { return nil }
                let model = ((item["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                let label: String
                switch kind {
                case "session": label = "Session (5h)"
                case "weekly_all": label = "Weekly"
                default: label = model.map { "Weekly · \($0)" } ?? kind
                }
                return UsageLimit(
                    kind: kind,
                    label: label,
                    percent: pct,
                    severity: item["severity"] as? String ?? "normal",
                    resetsAt: parseDate(item["resets_at"] as? String)
                )
            }
        }

        // Fallback: legacy five_hour / seven_day objects.
        var out: [UsageLimit] = []
        for (key, kind, label) in [("five_hour", "session", "Session (5h)"), ("seven_day", "weekly_all", "Weekly")] {
            if let obj = json[key] as? [String: Any], let u = (obj["utilization"] as? NSNumber)?.doubleValue {
                out.append(UsageLimit(kind: kind, label: label, percent: u, severity: "normal",
                                      resetsAt: parseDate(obj["resets_at"] as? String)))
            }
        }
        return out.isEmpty ? nil : out
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // Strip fractional seconds the formatter can't handle (e.g. microseconds).
        if let dot = s.firstIndex(of: "."), let tz = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            return f.date(from: String(s[..<dot]) + String(s[tz...]))
        }
        return nil
    }
}

// MARK: - View

private struct ClaudeUsageInlineView: View {
    @StateObject var model: UsageModel
    let showWeekly: Bool
    let showReset: Bool
    let colorize: Bool

    // Re-render the reset countdown each minute.
    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(model: UsageModel, showWeekly: Bool, showReset: Bool, colorize: Bool) {
        self.colorize = colorize
        _model = StateObject(wrappedValue: model)
        self.showWeekly = showWeekly
        self.showReset = showReset
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("CC")
                .font(BarFont.medium(10))
                .foregroundColor(.secondary)

            if let session = model.limits.first(where: { $0.kind == "session" }) {
                Text("\(pct(session))%")
                    .font(BarFont.regular(12))
                    .foregroundColor(color(for: session))
                if showReset, let reset = session.resetsAt {
                    Text(countdown(to: reset))
                        .font(BarFont.regular(10))
                        .foregroundColor(.secondary)
                }
            }

            if showWeekly, let weekly = model.limits.first(where: { $0.kind == "weekly_all" }) {
                Text("wk")
                    .font(BarFont.medium(10))
                    .foregroundColor(.secondary)
                Text("\(pct(weekly))%")
                    .font(BarFont.regular(12))
                    .foregroundColor(color(for: weekly))
                if showReset, let reset = weekly.resetsAt, reset > now {
                    Text(countdown(to: reset))
                        .font(BarFont.regular(10))
                        .foregroundColor(.secondary)
                }
            }

            if let error = model.error {
                Text(error)
                    .font(BarFont.regular(10))
                    .foregroundColor(.orange)
            } else if model.limits.isEmpty {
                Text(model.blockedUntil == nil ? "–" : "…")
                    .font(BarFont.regular(12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .help(tooltip)
        .contentShape(Rectangle())
        .onTapGesture { model.fetch() }
        .onReceive(tick) { now = $0 }
    }

    private var tooltip: String {
        var lines = model.limits.map { l -> String in
            var s = "\(l.label): \(pct(l))%"
            if let r = l.resetsAt {
                s += " — resets in \(countdown(to: r)) (\(r.formatted(date: .abbreviated, time: .shortened)))"
            }
            return s
        }
        if let until = model.blockedUntil {
            lines.append("Rate limited — retrying in \(countdown(to: until))")
        }
        if model.error == "stale" { lines.append("Token expired — run `claude` to refresh") }
        if let u = model.lastUpdated { lines.append("Updated \(u.formatted(date: .omitted, time: .standard)) · click to refresh") }
        return lines.joined(separator: "\n")
    }

    /// A cached value whose window has already reset is no longer meaningful; treat it as 0%.
    private func pct(_ l: UsageLimit) -> Int {
        if let r = l.resetsAt, r <= now { return 0 }
        return Int(l.percent.rounded())
    }

    private func color(for limit: UsageLimit) -> Color {
        guard colorize else { return .primary }
        switch limit.severity {
        case "normal":
            if limit.percent >= 90 { return .red }
            if limit.percent >= 75 { return .orange }
            return .primary
        case "warning", "elevated", "high": return .orange
        default: return .red
        }
    }

    private func countdown(to date: Date) -> String {
        let secs = max(0, Int(date.timeIntervalSince(now)))
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "\(d)d\(h)h" }
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }
}

// MARK: - Disk cache

/// Persists the last good response (and any active back-off) under
/// `~/.bottombar/cache/` so restarts show values immediately.
private struct DiskCache {
    let dataURL: URL
    let blockedURL: URL

    init(name: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bottombar/cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dataURL = dir.appendingPathComponent("\(name).json")
        blockedURL = dir.appendingPathComponent("\(name).blocked")
    }

    func load() -> (Data, Date)? {
        guard let data = try? Data(contentsOf: dataURL),
              let attrs = try? FileManager.default.attributesOfItem(atPath: dataURL.path),
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        return (data, mtime)
    }

    func save(_ data: Data) {
        try? data.write(to: dataURL, options: .atomic)
        try? FileManager.default.removeItem(at: blockedURL)
    }

    func loadBlockedUntil() -> Date? {
        guard let s = try? String(contentsOf: blockedURL, encoding: .utf8),
              let t = TimeInterval(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    func saveBlockedUntil(_ date: Date) {
        try? String(date.timeIntervalSince1970).write(to: blockedURL, atomically: true, encoding: .utf8)
    }
}
