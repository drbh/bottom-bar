import AppKit
import Combine
import SwiftUI
import BottomBarSDK

/// Shows CPU, RAM and (when the host has an NVIDIA GPU) VRAM for fleet hosts,
/// read over SSH from each host itself.
///
/// Each host gets one long-lived SSH session that runs a small `sh` loop
/// printing readings every `interval` seconds, so hardware-backed SSH keys
/// only sign once per connection. Targets go through `~/.ssh/config`, so the
/// fleet names (`nixos-fleet-vm-1`, ...) resolve through the tailnet proxy.
///
/// Config:
///   "hosts":    ["nixos-fleet-vm-1"]   // SSH targets (host or user@host)
///   "labels":   { "nixos-fleet-vm-1": "vm-1" }   // optional display names
///   "interval": 5
///   "color":    true                   // orange >=75%, red >=90%
///   "style":    "icons"                // "icons", "letters" (C/M/G) or "words"
///
/// - CPU: busy share of all cores, from /proc/stat deltas between readings.
/// - RAM: MemTotal minus MemAvailable, so page cache doesn't count as used.
/// - GPU: first GPU from `nvidia-smi`, shown only if the host has it.
class FleetBarPlugin: NSObject, BottomBarPlugin {
    let id = "fleet"
    let title = ""
    let icon = ""
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    private var hosts: [String] = ["nixos-fleet-vm-1"]
    private var labels: [String: String] = [:]
    private var interval: TimeInterval = 5
    private var colorize = true
    private var style = MetricStyle.icons

    func setConfiguration(_ config: [String: Any]) {
        if let h = config["hosts"] as? [Any], !h.isEmpty { hosts = h.map { "\($0)" } }
        if let h = config["host"] as? String, !h.isEmpty { hosts = [h] }
        if let l = config["labels"] as? [String: String] { labels = l }
        if let b = config["color"] as? Bool { colorize = b }
        if let s = config["style"] as? String, let st = MetricStyle(rawValue: s) { style = st }
        if let n = config["interval"] as? Double { interval = max(2, n) }
        if let n = config["interval"] as? Int { interval = max(2, Double(n)) }
    }

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: FleetInlineView(
            model: FleetModel(hosts: hosts, labels: labels, interval: Int(interval)),
            colorize: colorize, style: style))
    }
}

// MARK: - Readings

private enum MetricStyle: String {
    case icons, letters, words
}

private enum Metric {
    case cpu, mem, gpu

    var word: String {
        switch self { case .cpu: "cpu"; case .mem: "mem"; case .gpu: "gpu" }
    }

    var symbol: String {
        switch self { case .cpu: "cpu"; case .mem: "memorychip"; case .gpu: "display" }
    }
}

private struct GPUStat {
    let name: String
    let usedMiB: Double
    let totalMiB: Double
    let utilization: Double   // percent
}

private enum Reading {
    case cpu(total: Double, idle: Double, cores: Int)   // cumulative jiffies
    case mem(totalBytes: Double, availableBytes: Double)
    case uptime(Int)
    case gpu(GPUStat?)   // nil: nvidia-smi failed this round
}

/// Latest state of one host.
private struct HostStat {
    let target: String
    let label: String
    var online = false
    var cpu: Double? = nil          // 0...1 of all cores
    var cores = 0
    var memTotal: Double = 0        // bytes
    var memAvailable: Double = 0    // bytes
    var uptime = 0
    var gpu: GPUStat? = nil
    var hasGPU = false
    var lastUpdated: Date? = nil

    var memUsed: Double { max(0, memTotal - memAvailable) }
}

// MARK: - SSH stream

/// Keeps one SSH session open to a host, which prints readings every
/// `interval` seconds. Reconnects with exponential back-off when it ends.
private final class HostStream {
    private let target: String
    private let interval: Int
    private let onUpdate: (Reading?) -> Void   // nil: session ended; called on the main queue
    private var process: Process?
    private var failures = 0
    private var stopped = false
    private var retryGeneration = 0

    init(target: String, interval: Int, onUpdate: @escaping (Reading?) -> Void) {
        self.target = target
        self.interval = interval
        self.onUpdate = onUpdate
        start()
    }

    func stop() {
        stopped = true
        process?.terminate()
    }

    /// Connects now if the session is down, skipping the back-off wait.
    /// A live session is left alone: it already streams fresh readings.
    func reconnect() {
        guard process == nil else { return }
        failures = 0
        retryGeneration += 1   // drop the pending back-off retry
        start()
    }

    private func start() {
        guard !stopped, process == nil else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        // `sh -s` reads the script from stdin, so it doesn't depend on the
        // remote login shell or on quoting.
        proc.arguments = [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            target, "sh", "-s",
        ]
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
                let line = String(decoding: buffer[..<newline], as: UTF8.self)
                buffer.removeSubrange(...newline)
                guard let reading = Self.parse(line) else { continue }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.failures = 0
                    self.onUpdate(reading)
                }
            }
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.handleExit() }
        }

        do {
            try proc.run()
            process = proc
            input.fileHandleForWriting.write(Data(remoteScript().utf8))
            try? input.fileHandleForWriting.close()
        } catch {
            handleExit()
        }
    }

    private func handleExit() {
        process = nil
        onUpdate(nil)   // never show stale numbers
        guard !stopped else { return }
        // The tailnet SOCKS proxy flakes now and then, so retry quickly first.
        let delay = min(5 * pow(2, Double(failures)), 300)
        failures += 1
        let generation = retryGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.retryGeneration == generation else { return }
            self.start()
        }
    }

    /// Runs under `sh` on the host. When the connection drops, the loop dies
    /// of SIGPIPE on its next write.
    private func remoteScript() -> String {
        """
        while :; do
          read -r _ u ni s i w q sq st _ < /proc/stat
          echo "cpu $((u+ni+s+i+w+q+sq+st)) $((i+w)) $(nproc)"
          echo "mem $(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print t, a}' /proc/meminfo)"
          read -r up _ < /proc/uptime; echo "up ${up%.*}"
          if command -v nvidia-smi >/dev/null 2>&1; then
            g=$(nvidia-smi -i 0 --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null) && echo "gpu $g" || echo "gpu -"
          fi
          sleep \(max(1, interval))
        done

        """
    }

    private static func parse(_ line: String) -> Reading? {
        let parts = line.split(separator: " ")
        guard let kind = parts.first else { return nil }
        switch kind {
        case "cpu":
            guard parts.count == 4, let t = Double(parts[1]), let i = Double(parts[2]), let c = Int(parts[3]) else { return nil }
            return .cpu(total: t, idle: i, cores: c)
        case "mem":
            guard parts.count == 3, let t = Double(parts[1]), let a = Double(parts[2]), t > 0 else { return nil }
            return .mem(totalBytes: t * 1024, availableBytes: a * 1024)
        case "up":
            guard parts.count == 2, let u = Int(parts[1]) else { return nil }
            return .uptime(u)
        case "gpu":
            return .gpu(parseGPU(String(line.dropFirst(4))))
        default:
            return nil
        }
    }

    private static func parseGPU(_ line: String) -> GPUStat? {
        let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 4,
              let used = Double(parts[parts.count - 3]),
              let total = Double(parts[parts.count - 2]), total > 0 else { return nil }
        return GPUStat(name: parts.dropLast(3).joined(separator: ","),
                       usedMiB: used, totalMiB: total,
                       utilization: Double(parts[parts.count - 1]) ?? 0)
    }
}

// MARK: - Model

private class FleetModel: ObservableObject {
    @Published var stats: [HostStat]

    private var streams: [HostStream] = []
    private var lastCPU: [Int: (total: Double, idle: Double)] = [:]

    init(hosts: [String], labels: [String: String], interval: Int) {
        stats = hosts.map { HostStat(target: $0, label: labels[$0] ?? Self.defaultLabel($0)) }
        streams = hosts.indices.map { idx in
            HostStream(target: hosts[idx], interval: interval) { [weak self] reading in
                self?.apply(reading, to: idx)
            }
        }
    }

    deinit { streams.forEach { $0.stop() } }

    func reconnect() { streams.forEach { $0.reconnect() } }

    /// `drbh@nixos-fleet-vm-1` -> `nixos-fleet-vm-1`
    private static func defaultLabel(_ target: String) -> String {
        String(target.split(separator: "@").last ?? Substring(target))
    }

    private func apply(_ reading: Reading?, to idx: Int) {
        var s = stats[idx]
        switch reading {
        case nil:
            s = HostStat(target: s.target, label: s.label)
            lastCPU[idx] = nil
        case .cpu(let total, let idle, let cores):
            if let prev = lastCPU[idx], total > prev.total {
                s.cpu = min(1, max(0, 1 - (idle - prev.idle) / (total - prev.total)))
            }
            lastCPU[idx] = (total, idle)
            s.cores = cores
        case .mem(let total, let avail):
            s.memTotal = total
            s.memAvailable = avail
        case .uptime(let u):
            s.uptime = u
        case .gpu(let g):
            s.hasGPU = true
            s.gpu = g
        }
        if reading != nil {
            s.online = true
            s.lastUpdated = Date()
        }
        stats[idx] = s
    }
}

// MARK: - View

private struct FleetInlineView: View {
    @StateObject var model: FleetModel

    let colorize: Bool
    let style: MetricStyle

    init(model: FleetModel, colorize: Bool, style: MetricStyle) {
        self.colorize = colorize
        self.style = style
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.stats, id: \.target) { host in
                HStack(spacing: style == .words ? 4 : 3) {
                    Text(host.label)
                        .font(BarFont.medium(10))
                        .foregroundColor(.secondary)
                    if host.online {
                        label(.cpu)
                        Text(host.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                            .font(BarFont.regular(12))
                            .foregroundColor(color(host.cpu ?? 0))
                        if host.memTotal > 0 {
                            label(.mem)
                            Text("\(gb(host.memUsed))/\(gb(host.memTotal))G")
                                .font(BarFont.regular(12))
                                .foregroundColor(color(host.memUsed / host.memTotal))
                        }
                        if let gpu = host.gpu {
                            label(.gpu)
                            Text("\(gib(gpu.usedMiB))/\(gib(gpu.totalMiB))G")
                                .font(BarFont.regular(12))
                                .foregroundColor(color(gpu.usedMiB / gpu.totalMiB))
                        }
                    } else {
                        Text("offline")
                            .font(BarFont.regular(10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .help(tooltip)
        .contentShape(Rectangle())
        .onTapGesture { model.reconnect() }
    }

    @ViewBuilder
    private func label(_ metric: Metric) -> some View {
        switch style {
        case .icons:
            Image(systemName: metric.symbol)
                .font(BarFont.regular(10))
                .foregroundColor(.secondary)
                .padding(.leading, 2)
        case .letters:
            Text(metric.word.prefix(1).uppercased())
                .font(BarFont.medium(10))
                .foregroundColor(.secondary)
                .padding(.leading, 2)
        case .words:
            Text(metric.word)
                .font(BarFont.medium(10))
                .foregroundColor(.secondary)
        }
    }

    private var tooltip: String {
        var lines = model.stats.map { host -> String in
            guard host.online else {
                return "\(host.label): can't reach \(host.target) over SSH (tailnet proxy down?)"
            }
            let pct = host.memTotal > 0 ? Int((host.memUsed / host.memTotal * 100).rounded()) : 0
            var text = "\(host.label)"
                + (host.uptime > 0 ? " · up \(duration(host.uptime))" : "")
                + "\nRAM \(gb(host.memUsed)) / \(gb(host.memTotal)) GiB (\(pct)%) · \(gb(host.memAvailable)) GiB available"
                + "\nCPU \(host.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "–") of \(host.cores) cores"
            if let gpu = host.gpu {
                let vramPct = Int((gpu.usedMiB / gpu.totalMiB * 100).rounded())
                text += "\n\(gpu.name) · VRAM \(gib(gpu.usedMiB)) / \(gib(gpu.totalMiB)) GiB (\(vramPct)%) · load \(Int(gpu.utilization.rounded()))%"
            } else if host.hasGPU {
                text += "\nGPU unavailable (nvidia-smi failed)"
            }
            return text
        }
        if let u = model.stats.compactMap(\.lastUpdated).max() {
            lines.append("Updated \(u.formatted(date: .omitted, time: .standard))"
                + (model.stats.contains { !$0.online } ? " · click to reconnect" : ""))
        }
        return lines.joined(separator: "\n\n")
    }

    private func gb(_ bytes: Double) -> String {
        String(format: "%.1f", bytes / 1_073_741_824)
    }

    private func gib(_ mib: Double) -> String {
        String(format: "%.1f", mib / 1024)
    }

    private func color(_ pct: Double) -> Color {
        guard colorize else { return .primary }
        if pct >= 0.9 { return .red }
        if pct >= 0.75 { return .orange }
        return .primary
    }

    private func duration(_ secs: Int) -> String {
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "\(d)d\(h)h" }
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }
}
