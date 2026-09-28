import AppKit
import SwiftUI
import BottomBarSDK

class PRsBarPlugin: NSObject, BottomBarPlugin {
    let id = "prs"
    let title = ""
    let icon = ""
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: PRsInlineView())
    }
}

private class PRsModel: ObservableObject {
    @Published var count: Int? = nil
    @Published var error: String? = nil
    private var timer: Timer?

    init() {
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    private func fetch() {
        DispatchQueue.global(qos: .utility).async {
            guard let gh = ToolLocator.find("gh") else {
                DispatchQueue.main.async { self.error = "gh not found" }
                return
            }
            let proc = Process()
            proc.executableURL = gh
            proc.arguments = ["api", "search/issues?q=is:pr+author:@me+state:open+archived:false&per_page=1", "--jq", ".total_count"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let n = Int(str) {
                    DispatchQueue.main.async {
                        self.count = n
                        self.error = nil
                    }
                } else if proc.terminationStatus != 0 {
                    DispatchQueue.main.async { self.error = "run gh auth login" }
                }
            } catch {}
        }
    }
}

private struct PRsInlineView: View {
    @StateObject private var model = PRsModel()

    var body: some View {
        HStack(spacing: 3) {
            Text("PRs")
                .font(BarFont.medium(10))
                .foregroundColor(.secondary)
            if let error = model.error {
                Text(error)
                    .font(BarFont.regular(11))
                    .foregroundColor(.secondary)
            } else if let count = model.count {
                Text("\(count)")
                    .font(BarFont.regular(12))
            } else {
                Text("–")
                    .font(BarFont.regular(12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }
}
