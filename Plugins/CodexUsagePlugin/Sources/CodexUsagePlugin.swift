import AppKit
import Combine
import SwiftUI
import BottomBarSDK

/// Shows Codex CLI (ChatGPT plan) usage limits, from the same endpoint Codex's
/// `/status` uses. Reads the ChatGPT OAuth token Codex stores in
/// `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`) on every poll, so token
/// refreshes done by the CLI are picked up automatically.
///
/// Note: the endpoint is undocumented and may change.
class CodexUsageBarPlugin: NSObject, BottomBarPlugin {
    let id = "codex-usage"
    let title = ""
    let icon = ""
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    private var interval: TimeInterval = 60
    private var showReset = true
    private var colorize = true
    private var authPath: String = {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return (home as NSString).appendingPathComponent("auth.json")
        }
        return "~/.codex/auth.json"
    }()

    func setConfiguration(_ config: [String: Any]) {
        if let n = config["interval"] as? Double { interval = max(30, n) }
        if let n = config["interval"] as? Int { interval = max(30, Double(n)) }
        if let b = config["showReset"] as? Bool { showReset = b }
        if let b = config["color"] as? Bool { colorize = b }
        if let p = config["authPath"] as? String, !p.isEmpty { authPath = p }
    }

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: CodexUsageInlineView(
            model: CodexUsageModel(interval: interval, authPath: (authPath as NSString).expandingTildeInPath),
            showReset: showReset,
            colorize: colorize
        ))
    }
}

// MARK: - Model

private struct UsageWindow {
    let label: String
    let windowSeconds: Int
    let percent: Double
    let resetsAt: Date?
}

private enum UsageError: Error {
    case unauthorized, http(Int), parse
}

private class CodexUsageModel: ObservableObject {
    @Published var windows: [UsageWindow] = []
    @Published var limitReached = false
    @Published var plan: String? = nil
    @Published var error: String? = nil
    @Published var lastUpdated: Date? = nil
    @Published var blockedUntil: Date? = nil
    private var timer: Timer?
    private var consecutive429 = 0
    private let authPath: String
    private let cache = DiskCache(name: "codex-usage")

    init(interval: TimeInterval, authPath: String) {
        self.authPath = authPath
        // Show the last known values immediately so restarts don't flash "–".
        var age = TimeInterval.infinity
        if let (data, savedAt) = cache.load(), let p = Self.parse(data) {
            windows = p.windows
            limitReached = p.reached
            plan = p.plan
            lastUpdated = savedAt
            age = Date().timeIntervalSince(savedAt)
        }
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

    deinit { timer?.invalidate() }

    private func scheduleRetry(at until: Date) {
        blockedUntil = until
        DispatchQueue.main.asyncAfter(deadline: .now() + until.timeIntervalSinceNow + 1) { [weak self] in
            self?.blockedUntil = nil
            self?.fetch()
        }
    }

    func fetch() {
        if let until = blockedUntil, until > Date() { return }
        guard let (token, accountId) = readAuth() else {
            error = "no login"
            return
        }
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let accountId { req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id") }
        req.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var parsed: (windows: [UsageWindow], reached: Bool, plan: String?)? = nil
            var failure: UsageError? = nil
            var retryAfter: TimeInterval? = nil
            if status == 429 {
                retryAfter = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 120
                failure = .http(429)
            } else if status == 401 || status == 403 {
                failure = .unauthorized
            } else if status != 200 {
                failure = .http(status)
            } else if let data, err == nil, let p = Self.parse(data) {
                parsed = p
                self?.cache.save(data)
            } else {
                failure = .parse
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let retryAfter {
                    // Exponential back-off on repeated 429s (60s, 120s, 240s… up to 15m);
                        // the server's Retry-After is often 0 while still limiting.
                        self.consecutive429 += 1
                        let backoff = 60 * pow(2, Double(self.consecutive429 - 1))
                        let until = Date().addingTimeInterval(min(max(retryAfter, backoff), 900))
                    self.cache.saveBlockedUntil(until)
                    self.scheduleRetry(at: until)
                    return
                }
                if let parsed {
                    self.consecutive429 = 0
                    self.windows = parsed.windows
                    self.limitReached = parsed.reached
                    self.plan = parsed.plan
                    self.error = nil
                    self.lastUpdated = Date()
                    return
                }
                switch failure {
                case .unauthorized:
                    // Token expired; Codex refreshes it next time it runs.
                    self.error = "stale"
                case .http(let code):
                    // Keep last-known values on transient errors (e.g. 429).
                    if self.windows.isEmpty { self.error = code == 0 ? "offline" : "http \(code)" }
                default:
                    if self.windows.isEmpty { self.error = "err" }
                }
            }
        }.resume()
    }

    private func readAuth() -> (String, String?)? {
        guard let data = FileManager.default.contents(atPath: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty else {
            return nil
        }
        return (access, tokens["account_id"] as? String)
    }

    private static func parse(_ data: Data) -> (windows: [UsageWindow], reached: Bool, plan: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = json["rate_limit"] as? [String: Any] else { return nil }

        var windows: [UsageWindow] = []
        for key in ["primary_window", "secondary_window"] {
            guard let w = rl[key] as? [String: Any],
                  let pct = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
            let secs = (w["limit_window_seconds"] as? NSNumber)?.intValue ?? 0
            let reset = (w["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            windows.append(UsageWindow(label: windowLabel(secs), windowSeconds: secs, percent: pct, resetsAt: reset))
        }
        // Shortest window first (e.g. 5h before weekly).
        windows.sort { $0.windowSeconds < $1.windowSeconds }
        let reached = (rl["limit_reached"] as? Bool) ?? false
        return (windows, reached, json["plan_type"] as? String)
    }

    private static func windowLabel(_ secs: Int) -> String {
        switch secs {
        case 0: return "?"
        case 604800: return "wk"
        case let s where s % 86400 == 0: return "\(s / 86400)d"
        case let s where s % 3600 == 0: return "\(s / 3600)h"
        default: return "\(secs / 60)m"
        }
    }
}

// MARK: - View

private struct CodexUsageInlineView: View {
    @StateObject var model: CodexUsageModel
    let showReset: Bool
    let colorize: Bool

    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(model: CodexUsageModel, showReset: Bool, colorize: Bool) {
        self.colorize = colorize
        _model = StateObject(wrappedValue: model)
        self.showReset = showReset
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("CX")
                .font(BarFont.medium(10))
                .foregroundColor(.secondary)

            ForEach(Array(model.windows.enumerated()), id: \.offset) { idx, w in
                if idx > 0 {
                    Text(w.label)
                        .font(BarFont.medium(10))
                        .foregroundColor(.secondary)
                }
                Text("\(pct(w))%")
                    .font(BarFont.regular(12))
                    .foregroundColor(color(for: Double(pct(w))))
                // Countdown for the first (shortest) window, or whichever is maxed out.
                if showReset, let reset = w.resetsAt, reset > now, idx == 0 || pct(w) >= 100 {
                    Text(countdown(to: reset))
                        .font(BarFont.regular(10))
                        .foregroundColor(.secondary)
                }
            }

            if let error = model.error {
                Text(error)
                    .font(BarFont.regular(10))
                    .foregroundColor(.orange)
            } else if model.windows.isEmpty {
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
        var lines: [String] = []
        if let plan = model.plan { lines.append("Codex · \(plan)") }
        for w in model.windows {
            var s = "\(w.label) window: \(pct(w))%"
            if let r = w.resetsAt {
                s += " — resets in \(countdown(to: r)) (\(r.formatted(date: .abbreviated, time: .shortened)))"
            }
            lines.append(s)
        }
        if model.limitReached { lines.append("Limit reached") }
        if let until = model.blockedUntil { lines.append("Rate limited — retrying in \(countdown(to: until))") }
        if model.error == "stale" { lines.append("Token expired — run `codex` to refresh") }
        if let u = model.lastUpdated { lines.append("Updated \(u.formatted(date: .omitted, time: .standard)) · click to refresh") }
        return lines.joined(separator: "\n")
    }

    /// A cached value whose window has already reset is no longer meaningful; treat it as 0%.
    private func pct(_ w: UsageWindow) -> Int {
        if let r = w.resetsAt, r <= now { return 0 }
        return Int(w.percent.rounded())
    }

    private func color(for percent: Double) -> Color {
        guard colorize else { return .primary }
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        return .primary
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
