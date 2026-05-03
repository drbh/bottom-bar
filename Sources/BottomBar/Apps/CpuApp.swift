import SwiftUI
import Darwin

struct CpuBarItem: BottomBarItem {
    let id = "cpu"
    let title = ""
    let icon = ""
    let panelSize = CGSize.zero

    func makeContent(close: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
    }

    func makeBarView() -> AnyView? {
        AnyView(CpuInlineView())
    }
}

private class CpuModel: ObservableObject {
    @Published var usage: String = "  0%"
    private var timer: Timer?
    private var prevInfo: host_cpu_load_info?

    init() {
        prevInfo = getCpuLoadInfo()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    private func update() {
        guard let prev = prevInfo, let cur = getCpuLoadInfo() else { return }

        let userDiff = Double(cur.cpu_ticks.0 - prev.cpu_ticks.0)
        let sysDiff = Double(cur.cpu_ticks.1 - prev.cpu_ticks.1)
        let idleDiff = Double(cur.cpu_ticks.2 - prev.cpu_ticks.2)
        let niceDiff = Double(cur.cpu_ticks.3 - prev.cpu_ticks.3)

        let total = userDiff + sysDiff + idleDiff + niceDiff
        let used = userDiff + sysDiff + niceDiff
        let pct = total > 0 ? (used / total) * 100 : 0

        prevInfo = cur

        DispatchQueue.main.async {
            self.usage = String(format: "%3.0f%%", pct)
        }
    }

    private func getCpuLoadInfo() -> host_cpu_load_info? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &size)
            }
        }

        return result == KERN_SUCCESS ? info : nil
    }
}

private struct CpuInlineView: View {
    @StateObject private var model = CpuModel()

    var body: some View {
        HStack(spacing: 3) {
            Text("CPU")
                .font(BarFont.medium(10))
                .foregroundColor(.secondary)
            Text(model.usage)
                .font(BarFont.regular(12))
        }
        .padding(.horizontal, 6)
    }
}
