import SwiftUI
import Darwin

struct MemoryBarItem: BottomBarItem {
    let id = "memory"
    let title = ""
    let icon = ""
    let panelSize = CGSize.zero

    func makeContent(close: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
    }

    func makeBarView() -> AnyView? {
        AnyView(MemoryInlineView())
    }
}

private struct MemoryInlineView: View {
    @State private var usage = MemoryUsage(used: 0, total: 0)
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "memorychip")
                .font(BarFont.regular(10))
                .foregroundColor(.secondary)
            Text(label)
                .font(BarFont.regular(12))
        }
        .padding(.horizontal, 6)
        .onAppear { usage = fetchMemory() }
        .onReceive(timer) { _ in usage = fetchMemory() }
    }

    private var label: String {
        let usedGB = Double(usage.used) / (1024 * 1024 * 1024)
        let totalGB = Double(usage.total) / (1024 * 1024 * 1024)
        return String(format: "%.1f/%.0fG", usedGB, totalGB)
    }

    private func fetchMemory() -> MemoryUsage {
        let total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryUsage(used: 0, total: total)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed

        return MemoryUsage(used: used, total: total)
    }
}

private struct MemoryUsage {
    let used: UInt64
    let total: UInt64
}
