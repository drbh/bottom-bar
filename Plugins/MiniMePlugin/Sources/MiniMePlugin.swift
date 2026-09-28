import AppKit
import SwiftUI
import BottomBarSDK

class MiniMeBarPlugin: NSObject, BottomBarPlugin {
    let id = "minime"
    let title = "MiniMe"
    let icon = "person.fill"
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    /// Executable name or path, overridable via `"config": { "command": "..." }`.
    private var command = "minime"

    func setConfiguration(_ config: [String: Any]) {
        if let command = config["command"] as? String, !command.isEmpty {
            self.command = command
        }
    }

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        let model = MiniMeModel(command: command)
        return NSHostingView(rootView: MiniMeInlineView(model: model))
    }
}

private class MiniMeModel: ObservableObject {
    @Published var isRunning = false
    let executable: URL?
    private let processName: String
    private var timer: Timer?

    init(command: String) {
        executable = ToolLocator.find(command)
        processName = (command as NSString).lastPathComponent
        checkRunning()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkRunning()
        }
    }

    func isMiniMe(_ app: NSRunningApplication) -> Bool {
        app.localizedName == processName || (executable != nil && app.executableURL == executable)
    }

    private func checkRunning() {
        let running = NSWorkspace.shared.runningApplications.contains(where: isMiniMe)
        DispatchQueue.main.async {
            self.isRunning = running
        }
    }
}

private struct MiniMeInlineView: View {
    @StateObject var model: MiniMeModel
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
        .disabled(model.executable == nil)
        .help(model.executable == nil ? "minime not found" : "")
        .onHover { isHovered = $0 }
    }

    private func toggle() {
        if model.isRunning {
            // Kill running minime processes
            for app in NSWorkspace.shared.runningApplications where model.isMiniMe(app) {
                app.terminate()
            }
        } else if let executable = model.executable {
            DispatchQueue.global().async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                // Login shell so minime gets the user's environment.
                proc.arguments = ["-l", "-c", "exec \"$0\"", executable.path]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                try? proc.run()
            }
        }
    }
}
