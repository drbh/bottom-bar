import AppKit
import SwiftUI
import BottomBarSDK

class AerospaceBarPlugin: NSObject, BottomBarPlugin {
    let id = "aerospace"
    let title = ""
    let icon = ""
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: AerospaceInlineView())
    }
}

private struct WorkspaceInfo: Identifiable {
    let id: String
    let windowCount: Int
    let isFocused: Bool
}

private struct AerospaceInlineView: View {
    @State private var workspaces: [WorkspaceInfo] = []
    private let aerospace = ToolLocator.find("aerospace")
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.grid.2x2")
                .font(BarFont.regular(10))
                .foregroundColor(.secondary)

            if aerospace == nil {
                Text("aerospace not found")
                    .font(BarFont.regular(11))
                    .foregroundColor(.secondary)
            }

            ForEach(workspaces) { ws in
                HStack(spacing: 2) {
                    Text(ws.id)
                        .font(ws.isFocused ? BarFont.bold(11) : BarFont.regular(11))
                    Text("\(ws.windowCount)")
                        .font(BarFont.medium(9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ws.isFocused ? Color.primary.opacity(0.15) : Color.clear)
                )
            }
        }
        .padding(.horizontal, 6)
        .onAppear { refresh() }
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        guard aerospace != nil else { return }
        let focused = run("list-workspaces", ["--focused"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let windowWorkspaces = run("list-windows", ["--all", "--format", "%{workspace}"])
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var counts: [String: Int] = [:]
        for ws in windowWorkspaces where !ws.isEmpty {
            counts[ws, default: 0] += 1
        }

        workspaces = counts.keys
            .sorted()
            .map { WorkspaceInfo(id: $0, windowCount: counts[$0]!, isFocused: $0 == focused) }
    }

    private func run(_ subcommand: String, _ args: [String]) -> String {
        guard let aerospace else { return "" }
        let proc = Process()
        proc.executableURL = aerospace
        proc.arguments = [subcommand] + args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
