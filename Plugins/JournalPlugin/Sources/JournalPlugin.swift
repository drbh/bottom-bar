import AppKit
import SwiftUI
import BottomBarSDK

class JournalBarPlugin: NSObject, BottomBarPlugin {
    let id = "journal"
    let title = ""
    let icon = "calendar"
    let panelWidth: CGFloat = 280
    let panelHeight: CGFloat = 284

    private var store = JournalStore(
        root: URL(fileURLWithPath: NSString(string: "~/journal").expandingTildeInPath),
        editorBundleID: "dev.zed.Zed"
    )

    func setConfiguration(_ config: [String: Any]) {
        if let path = config["path"] as? String {
            store.root = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }
        if let editor = config["editor"] as? String {
            store.editorBundleID = editor
        }
    }

    func makeContentView(close: @escaping () -> Void) -> NSView {
        NSHostingView(rootView: JournalPanelView(store: store, close: close))
    }
}

private struct JournalStore {
    var root: URL
    var editorBundleID: String

    func url(for date: Date) -> URL {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return root
            .appendingPathComponent(String(format: "%04d", c.year!))
            .appendingPathComponent(String(format: "%02d", c.month!))
            .appendingPathComponent(String(format: "%02d", c.day!))
    }

    func daysWithEntries(inMonthOf date: Date) -> Set<Int> {
        let dir = url(for: date).deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return Set(names.compactMap { $0.hasSuffix(".md") ? Int($0.prefix { $0 != "." }) : nil })
    }

    func open(_ date: Date) {
        let base = url(for: date)
        let legacy = base.appendingPathExtension("md")
        let file = FileManager.default.fileExists(atPath: legacy.path)
            ? legacy
            : base.appendingPathExtension("x.md")
        if !FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            try? "# \(f.string(from: Date()))\n\n".write(to: file, atomically: true, encoding: .utf8)
        }
        if !editorBundleID.isEmpty,
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editorBundleID) {
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(file)
        }
    }
}

private struct JournalPanelView: View {
    let store: JournalStore
    let close: () -> Void
    @State private var month = Date()
    @State private var entries: Set<Int> = []

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 8) {
            header
            Divider().opacity(0.5)
            weekdayRow
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(cells, id: \.self) { date in
                    let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                    DayCell(
                        day: calendar.component(.day, from: date),
                        isToday: calendar.isDateInToday(date),
                        inMonth: inMonth,
                        hasEntry: inMonth && entries.contains(calendar.component(.day, from: date))
                    ) {
                        store.open(date)
                        close()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { month = Date(); refresh() }
    }

    private var header: some View {
        HStack {
            Text(monthTitle).font(.system(size: 13, weight: .semibold))
            Spacer()
            HStack(spacing: 2) {
                HeaderButton(label: Image(systemName: "chevron.left")) { shift(-1) }
                HeaderButton(label: Text("Today")) { month = Date(); refresh() }
                HeaderButton(label: Image(systemName: "chevron.right")) { shift(1) }
            }
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: month)
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var cells: [Date] {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - leading, to: start) }
    }

    private func shift(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month) ?? month
        refresh()
    }

    private func refresh() {
        entries = store.daysWithEntries(inMonthOf: month)
    }
}

private struct HeaderButton<Label: View>: View {
    let label: Label
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct DayCell: View {
    let day: Int
    let isToday: Bool
    let inMonth: Bool
    let hasEntry: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                    .foregroundColor(isToday ? .white : (inMonth ? .primary : .secondary.opacity(0.5)))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(circleFill))
                Circle()
                    .fill(hasEntry ? Color.accentColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var circleFill: Color {
        if isToday { return Color.accentColor }
        return Color.primary.opacity(isHovered ? 0.12 : 0)
    }
}
