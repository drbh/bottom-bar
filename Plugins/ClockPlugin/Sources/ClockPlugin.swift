import AppKit
import SwiftUI
import BottomBarSDK

class ClockBarPlugin: NSObject, BottomBarPlugin {
    let id = "clock"
    let title = ""
    let icon = ""
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0
    let side = "right"

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: WorldClocksView())
    }
}

private struct WorldClocksView: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let zones: [(label: String, tz: TimeZone)] = [
        ("JP", TimeZone(identifier: "Asia/Tokyo")!),
        ("UTC", TimeZone(identifier: "UTC")!),
        ("CET", TimeZone(identifier: "Europe/Paris")!),
        ("CA", TimeZone(identifier: "America/Los_Angeles")!),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(Self.zones.enumerated()), id: \.offset) { _, zone in
                HStack(spacing: 3) {
                    Text(zone.label)
                        .font(BarFont.medium(10))
                        .foregroundColor(.white.opacity(0.6))
                    Text(timeString(for: zone.tz))
                        .font(BarFont.regular(12))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 6)
        .onReceive(timer) { now = $0 }
    }

    private func timeString(for tz: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = "h:mm a"
        return f.string(from: now)
    }
}
