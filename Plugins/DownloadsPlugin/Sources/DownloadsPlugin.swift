import AppKit
import SwiftUI
import BottomBarSDK

class DownloadsBarPlugin: NSObject, BottomBarPlugin {
    let id = "downloads"
    let title = "Downloads"
    let icon = "arrow.down.circle"
    let panelWidth: CGFloat = 300
    let panelHeight: CGFloat = 600

    func makeContentView(close: @escaping () -> Void) -> NSView {
        NSHostingView(rootView: DownloadsPanelView(close: close))
    }

    func makeBarNSView() -> NSView? {
        nil
    }
}

private struct DownloadEntry: Identifiable {
    let id: String
    let name: String
    let modified: Date
    let size: Int64
    let url: URL
}

private struct DownloadsPanelView: View {
    let close: () -> Void
    @State private var files: [DownloadEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(files) { file in
                DownloadRow(file: file, close: close)
            }
        }
        .padding(.vertical, 4)
        .onAppear { refresh() }
    }

    private func refresh() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        files = contents
            .compactMap { url -> DownloadEntry? in
                let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let date = vals?.contentModificationDate ?? .distantPast
                let size = Int64(vals?.fileSize ?? 0)
                return DownloadEntry(
                    id: url.lastPathComponent,
                    name: url.lastPathComponent,
                    modified: date,
                    size: size,
                    url: url
                )
            }
            .sorted { $0.modified > $1.modified }
            .prefix(20)
            .map { $0 }
    }
}

private struct DownloadRow: View {
    let file: DownloadEntry
    let close: () -> Void
    @State private var isHovered = false

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        Button(action: openFile) {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(file.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isHovered ? .white : .primary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatSize(file.size))
                        .font(.system(size: 10))
                    Text(Self.dateFormatter.localizedString(for: file.modified, relativeTo: Date()))
                        .font(.system(size: 10))
                }
                .foregroundColor(isHovered ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor : Color.clear)
                    .opacity(isHovered ? 0.8 : 0)
                    .padding(.horizontal, 5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func openFile() {
        NSWorkspace.shared.open(file.url)
        close()
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        } else if bytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } else if bytes >= 1_000 {
            return String(format: "%.0f KB", Double(bytes) / 1_000)
        } else {
            return "\(bytes) B"
        }
    }
}
