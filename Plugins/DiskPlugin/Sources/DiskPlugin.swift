import AppKit
import SwiftUI
import BottomBarSDK

class DiskBarPlugin: NSObject, BottomBarPlugin {
    let id = "disk"
    let title = ""
    let icon = ""
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: DiskInlineView())
    }
}

private class DiskModel: ObservableObject {
    @Published var label: String = ""
    private var timer: Timer?

    init() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    private func update() {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) else { return }
        let total = values.volumeTotalCapacity ?? 0
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        let used = Int64(total) - available
        let usedGB = Double(used) / 1_000_000_000
        let totalGB = Double(total) / 1_000_000_000
        DispatchQueue.main.async {
            self.label = String(format: "%.0f/%.0fG", usedGB, totalGB)
        }
    }
}

private struct DiskInlineView: View {
    @StateObject private var model = DiskModel()

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "internaldrive")
                .font(BarFont.regular(10))
                .foregroundColor(.secondary)
            Text(model.label)
                .font(BarFont.regular(12))
        }
        .padding(.horizontal, 6)
    }
}
