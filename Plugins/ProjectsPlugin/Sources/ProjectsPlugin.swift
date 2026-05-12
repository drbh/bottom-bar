import AppKit
import SwiftUI
import BottomBarSDK

class ProjectsBarPlugin: NSObject, BottomBarPlugin {
    let id = "projects"
    let title = "Projects"
    let icon = "folder"
    let panelWidth: CGFloat = 250
    let panelHeight: CGFloat = 580

    func makeContentView(close: @escaping () -> Void) -> NSView {
        NSHostingView(rootView: ProjectsPanelView(close: close))
    }

    func makeBarNSView() -> NSView? {
        nil
    }
}

private struct ProjectEntry: Identifiable {
    let id: String
    let name: String
    let modified: Date
}

private struct ProjectsPanelView: View {
    let close: () -> Void
    @State private var projects: [ProjectEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(projects) { project in
                ProjectRow(project: project, close: close)
            }
        }
        .padding(.vertical, 4)
        .onAppear { refresh() }
    }

    private func refresh() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        projects = contents
            .compactMap { url -> ProjectEntry? in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      isDir.boolValue else { return nil }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return ProjectEntry(id: url.lastPathComponent, name: url.lastPathComponent, modified: date)
            }
            .sorted { $0.modified > $1.modified }
            .prefix(40)
            .map { $0 }
    }
}

private struct ProjectRow: View {
    let project: ProjectEntry
    let close: () -> Void
    @State private var isHovered = false

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        Button(action: openProject) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                Text(project.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Spacer()
                Text(Self.formatter.localizedString(for: project.modified, relativeTo: Date()))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor : Color.clear)
                    .opacity(isHovered ? 0.8 : 0)
                    .padding(.horizontal, 5)
            )
            .foregroundColor(isHovered ? .white : .primary)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func openProject() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects")
            .appendingPathComponent(project.name)
        NSWorkspace.shared.open(path)
        close()
    }
}
