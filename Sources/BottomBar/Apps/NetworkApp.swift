import SwiftUI
import Darwin

struct NetworkBarItem: BottomBarItem {
    let id = "network"
    let title = ""
    let icon = ""
    let panelSize = CGSize.zero

    func makeContent(close: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
    }

    func makeBarView() -> AnyView? {
        AnyView(NetworkInlineView())
    }
}

private class NetworkModel: ObservableObject {
    @Published var downRate: String = "000.0B"
    @Published var upRate: String = "000.0B"

    private var timer: Timer?
    private var lastIn: UInt64 = 0
    private var lastOut: UInt64 = 0
    private var lastTime: Date = Date()

    init() {
        let (bytesIn, bytesOut) = Self.getBytes()
        lastIn = bytesIn
        lastOut = bytesOut
        lastTime = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    private func update() {
        let (bytesIn, bytesOut) = Self.getBytes()
        let now = Date()
        let dt = now.timeIntervalSince(lastTime)
        guard dt > 0 else { return }

        let dIn = bytesIn >= lastIn ? bytesIn - lastIn : bytesIn
        let dOut = bytesOut >= lastOut ? bytesOut - lastOut : bytesOut

        let inPerSec = Double(dIn) / dt
        let outPerSec = Double(dOut) / dt

        lastIn = bytesIn
        lastOut = bytesOut
        lastTime = now

        DispatchQueue.main.async {
            self.downRate = Self.format(inPerSec)
            self.upRate = Self.format(outPerSec)
        }
    }

    private static func format(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_000_000_000 {
            return String(format: "%05.1fG", bytesPerSec / 1_000_000_000)
        } else if bytesPerSec >= 1_000_000 {
            return String(format: "%05.1fM", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 1_000 {
            return String(format: "%05.1fK", bytesPerSec / 1_000)
        } else {
            return String(format: "%05.1fB", bytesPerSec)
        }
    }

    private static func getBytes() -> (UInt64, UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = ptr {
            let name = String(cString: addr.pointee.ifa_name)
            // Only count physical-ish interfaces
            if name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("pdp_ip") {
                if let data = addr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalIn += UInt64(networkData.ifi_ibytes)
                    totalOut += UInt64(networkData.ifi_obytes)
                }
            }
            ptr = addr.pointee.ifa_next
        }

        return (totalIn, totalOut)
    }
}

private struct NetworkInlineView: View {
    @StateObject private var model = NetworkModel()

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                Image(systemName: "arrow.down")
                    .font(BarFont.bold(8))
                    .foregroundColor(.secondary)
                Text(model.downRate)
                    .font(BarFont.regular(12))
                    .fixedSize()
            }
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(BarFont.bold(8))
                    .foregroundColor(.secondary)
                Text(model.upRate)
                    .font(BarFont.regular(12))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 6)
    }
}
