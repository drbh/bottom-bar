import AppKit
import Combine
import SwiftUI
import BottomBarSDK

/// Shows what the agents and other programs in Rex terminals are doing, from
/// the status they report with the Program Status Protocol (OSC 7501):
/// how many are working, blocked on you, done, or failed.
///
/// One long-lived `rex do --all` process runs a Lua script that prints a JSON
/// snapshot of every session's status records whenever one changes, so the
/// bar updates as soon as an agent does.
///
/// Click to list the sessions with a status; pick one to switch the Rex app to
/// that session and terminal.
///
/// Config:
///   "rex":      "rex"      // path or name of the rex CLI
///   "showIdle": false      // also count programs reporting "idle"
///   "color":    true       // tint blocked/done/error counts
class RexBarPlugin: NSObject, BottomBarPlugin {
    let id = "rex"
    let title = ""
    let icon = ""
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    private var rexPath = "rex"
    private var showIdle = false
    private var colorize = true

    func setConfiguration(_ config: [String: Any]) {
        if let p = config["rex"] as? String, !p.isEmpty { rexPath = p }
        if let b = config["showIdle"] as? Bool { showIdle = b }
        if let b = config["color"] as? Bool { colorize = b }
    }

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    /// Finds the rex CLI. Apps launched from Finder don't get the shell's PATH.
    /// (Not ToolLocator: older BottomBar builds ship an SDK without it.)
    private static func locate(_ name: String) -> URL? {
        let fm = FileManager.default
        let expanded = (name as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return fm.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        let home = fm.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            .map { "\($0)/\(name)" }
            .first { fm.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: RexInlineView(
            model: RexModel(rex: Self.locate(rexPath)),
            showIdle: showIdle, colorize: colorize))
    }
}

// MARK: - Model

/// The states of the Program Status Protocol, most urgent first.
private enum AgentState: String, CaseIterable {
    case blocked, error, done, working, idle

    var symbol: String {
        switch self {
        case .blocked: "hand.raised.fill"
        case .error: "exclamationmark.triangle.fill"
        case .done: "checkmark.circle.fill"
        case .working: "arrow.triangle.2.circlepath"
        case .idle: "moon.zzz"
        }
    }

    var tint: Color {
        switch self {
        case .blocked: .orange
        case .error: .red
        case .done: .green
        case .working, .idle: .primary
        }
    }
}

private struct Agent {
    let sessionID: String
    let sessionLabel: String
    let blockID: String
    let state: AgentState
    let app: String
    let message: String
    let updated: Date?
}

private class RexModel: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var connected = false

    let rex: URL?
    private var stream: RexStream?

    init(rex: URL?) {
        self.rex = rex
        guard let rex else { return }
        stream = RexStream(rex: rex) { [weak self] agents in
            guard let self else { return }
            self.connected = agents != nil
            self.agents = agents ?? []
        }
    }

    deinit { stream?.stop() }

    func count(_ state: AgentState) -> Int {
        agents.reduce(0) { $0 + ($1.state == state ? 1 : 0) }
    }

    /// Agents worth listing, most urgent first, then most recent.
    func sorted(includeIdle: Bool) -> [Agent] {
        let order = Dictionary(uniqueKeysWithValues: AgentState.allCases.enumerated().map { ($1, $0) })
        return agents
            .filter { includeIdle || $0.state != .idle }
            .sorted {
                if $0.state != $1.state { return order[$0.state]! < order[$1.state]! }
                return ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast)
            }
    }

    /// Switches the Rex app to the agent's session and terminal.
    func jump(to agent: Agent) {
        guard let rex else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            Self.run(rex, ["--autostart=false", "do", "session.select", "session_id=\(agent.sessionID)"])
            Self.run(rex, ["--autostart=false", "focus", "-s", agent.sessionID, agent.blockID])
            DispatchQueue.main.async {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.superlogical.rex")
                    .first?.activate()
            }
        }
    }

    private static func run(_ exe: URL, _ args: [String]) {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}

// MARK: - Stream

/// Runs `rex do --all -` with a Lua script that prints a snapshot line on
/// every status change. Restarts with back-off when it exits (Rex quit,
/// server restarting, ...).
private final class RexStream {
    private let rex: URL
    private let onUpdate: ([Agent]?) -> Void   // nil: disconnected; called on the main queue
    private var process: Process?
    private var failures = 0
    private var stopped = false

    init(rex: URL, onUpdate: @escaping ([Agent]?) -> Void) {
        self.rex = rex
        self.onUpdate = onUpdate
        start()
    }

    func stop() {
        stopped = true
        process?.terminate()
    }

    private func start() {
        guard !stopped, process == nil else { return }
        let proc = Process()
        proc.executableURL = rex
        // Never start a server just to watch it; wait for Rex to be running.
        proc.arguments = ["--autostart=false", "do", "--all", "-"]
        let out = Pipe()
        let input = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = input

        var buffer = Data()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let agents = Self.parse(Data(line)) else { continue }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.failures = 0
                    self.onUpdate(agents)
                }
            }
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.handleExit() }
        }

        do {
            try proc.run()
            process = proc
            input.fileHandleForWriting.write(Data(Self.script.utf8))
            try? input.fileHandleForWriting.close()
        } catch {
            handleExit()
        }
    }

    private func handleExit() {
        process = nil
        onUpdate(nil)
        guard !stopped else { return }
        let delay = min(3 * pow(2, Double(failures)), 60)
        failures += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.start() }
    }

    private static let dateParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Rex sends microseconds; ISO8601DateFormatter takes at most milliseconds.
    private static func parseDate(_ s: String?) -> Date? {
        guard var s else { return nil }
        if let dot = s.firstIndex(of: "."),
           let end = s[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }),
           s.distance(from: dot, to: end) > 4 {
            s.replaceSubrange(s.index(dot, offsetBy: 4)..<end, with: "")
        }
        return dateParser.date(from: s)
    }

    /// Parses one snapshot line. Non-JSON lines (such as rex's "listening"
    /// banner) and error lines return nil.
    private static func parse(_ data: Data) -> [Agent]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessions = json["sessions"] as? [[String: Any]] else { return nil }
        var agents: [Agent] = []
        for s in sessions {
            let sid = s["id"] as? String ?? ""
            let label = (s["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? String(sid.suffix(6))
            // Lua encodes an empty table as {} rather than [].
            for r in s["records"] as? [[String: Any]] ?? [] {
                guard let state = AgentState(rawValue: r["state"] as? String ?? "") else { continue }
                agents.append(Agent(
                    sessionID: sid, sessionLabel: label,
                    blockID: r["block"] as? String ?? "",
                    state: state,
                    app: r["app"] as? String ?? "",
                    message: r["msg"] as? String ?? "",
                    updated: parseDate(r["at"] as? String)))
            }
        }
        return agents
    }

    /// Prints {"sessions":[{id,label,records:[{block,state,app,msg,at}]}]}
    /// once at start, after every status change (debounced), and every 30s.
    private static let script = """
    local TERM = "com.superlogical.terminal"

    local function emit(v)
      io.write(rex.json.encode(v), "\\n")
      io.stdout:flush()
    end

    local function snapshot()
      local list, err = rex.call("session.list")
      if not list then return emit({ error = tostring(err) }) end
      local out = {}
      for _, s in ipairs(list.sessions or {}) do
        local records = {}
        local blocks = rex.call("session.list_blocks", { session_id = s.session_id })
        for _, b in ipairs((blocks and blocks.blocks) or {}) do
          if b.creator_name == TERM then
            local st = rex.call("block.method", { session_id = s.session_id, block_id = b.block_id, method = "program_status" })
            for _, r in ipairs((st and st.records) or {}) do
              records[#records + 1] = { block = b.block_id, state = r.state, app = r.effective_app or r.app, msg = r.msg, at = r.updated_at }
            end
          end
        end
        out[#out + 1] = { id = s.session_id, label = s.label or "", records = records }
      end
      emit({ sessions = out })
    end

    local pending
    local function soon()
      if pending then pending:cancel() end
      pending = rex.after(0.3, snapshot)
    end

    for _, name in ipairs({
      "terminal.program_status_changed", "terminal.program_status_removed",
      "session_created", "session_destroyed", "session_label_changed",
      "block_created", "block_closed",
    }) do
      rex.on(name, function() soon() end)
    end
    rex.every(30, snapshot)
    -- The first snapshot waits until the script hears every session.
    rex.after(0, snapshot)

    """
}

// MARK: - View

private struct RexInlineView: View {
    @StateObject var model: RexModel

    let showIdle: Bool
    let colorize: Bool

    init(model: RexModel, showIdle: Bool, colorize: Bool) {
        self.showIdle = showIdle
        self.colorize = colorize
        _model = StateObject(wrappedValue: model)
    }

    private var shownStates: [AgentState] {
        AgentState.allCases.filter { ($0 != .idle || showIdle) && model.count($0) > 0 }
    }

    var body: some View {
        HStack(spacing: 6) {
            if shownStates.isEmpty {
                Image(systemName: "terminal")
                    .font(BarFont.regular(10))
                    .foregroundColor(.secondary)
                if !model.connected {
                    Text(model.rex == nil ? "no rex" : "off")
                        .font(BarFont.regular(10))
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(shownStates, id: \.self) { state in
                    HStack(spacing: 2) {
                        Image(systemName: state.symbol)
                            .font(BarFont.regular(10))
                            .foregroundColor(colorize && state.tint != .primary ? state.tint : .secondary)
                        Text("\(model.count(state))")
                            .font(BarFont.regular(12))
                            .foregroundColor(colorize ? state.tint : .primary)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .help(tooltip)
        .contentShape(Rectangle())
        .onTapGesture { showMenu() }
    }

    private func line(_ a: Agent) -> String {
        var text = "\(a.sessionLabel) · \(a.app.isEmpty ? "program" : a.app) · \(a.state.rawValue)"
        if let u = a.updated, a.state != .working { text += " \(age(u))" }
        if !a.message.isEmpty { text += " — \(a.message.count > 60 ? a.message.prefix(59) + "…" : a.message)" }
        return text
    }

    private var tooltip: String {
        if model.rex == nil { return "rex CLI not found" }
        if !model.connected { return "Rex isn't running" }
        let agents = model.sorted(includeIdle: showIdle)
        if agents.isEmpty { return "No programs reporting status in Rex" }
        return (agents.map(line) + ["Click to jump to a session"]).joined(separator: "\n")
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let agents = model.sorted(includeIdle: true)
        if agents.isEmpty {
            let item = NSMenuItem(title: model.connected ? "No programs reporting status" : "Rex isn't running",
                                  action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for agent in agents {
            let item = ClosureMenuItem(title: line(agent)) { [model] in model.jump(to: agent) }
            item.image = NSImage(systemSymbolName: agent.state.symbol, accessibilityDescription: agent.state.rawValue)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func age(_ date: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(date)))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}

/// An NSMenuItem that runs a closure when chosen.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}
