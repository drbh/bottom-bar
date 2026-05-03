import SwiftUI

struct UptimeBarItem: BottomBarItem {
    let id = "uptime"
    let title = ""
    let icon = ""
    let panelSize = CGSize.zero

    func makeContent(close: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
    }

    func makeBarView() -> AnyView? {
        AnyView(UptimeInlineView())
    }
}

private class UptimeModel: ObservableObject {
    @Published var uptime: String = ""
    private var timer: Timer?

    init() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    private func update() {
        let totalSeconds = Int(ProcessInfo.processInfo.systemUptime)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let mins = (totalSeconds % 3600) / 60

        DispatchQueue.main.async {
            if days > 0 {
                self.uptime = "\(days)d \(hours)h \(mins)m"
            } else if hours > 0 {
                self.uptime = "\(hours)h \(mins)m"
            } else {
                self.uptime = "\(mins)m"
            }
        }
    }
}

private struct UptimeInlineView: View {
    @StateObject private var model = UptimeModel()

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.up.circle")
                .font(BarFont.regular(10))
                .foregroundColor(.secondary)
            Text(model.uptime)
                .font(BarFont.regular(12))
        }
        .padding(.horizontal, 6)
    }
}
