import AppKit
import SwiftUI
import BottomBarSDK

class MiniMeBarPlugin: NSObject, BottomBarPlugin {
    let id = "minime"
    let title = "MiniMe"
    let icon = "person.fill"
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: MiniMeInlineView())
    }
}

private class MiniMeModel: ObservableObject {
    @Published var isRunning = false
    private var timer: Timer?

    init() {
        checkRunning()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkRunning()
        }
    }

    private func checkRunning() {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.localizedName == "minime" || $0.executableURL?.path == "/Users/drbh/.cargo/bin/minime"
        }
        DispatchQueue.main.async {
            self.isRunning = running
        }
    }
}

private struct MiniMeInlineView: View {
    @StateObject private var model = MiniMeModel()
    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 3) {
                Circle()
                    .fill(model.isRunning ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 6, height: 6)
                Image(systemName: "person.fill")
                    .font(BarFont.regular(10))
                    .foregroundColor(model.isRunning ? .white : .secondary)
                Text("MiniMe")
                    .font(BarFont.regular(12))
                    .foregroundColor(model.isRunning ? .white : .secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.white.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func toggle() {
        if model.isRunning {
            // Kill running minime processes
            for app in NSWorkspace.shared.runningApplications
                where app.localizedName == "minime" || app.executableURL?.path == "/Users/drbh/.cargo/bin/minime" {
                app.terminate()
            }
        } else {
            DispatchQueue.global().async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-l", "-c", "/Users/drbh/.cargo/bin/minime"]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                try? proc.run()
            }
        }
    }
}
