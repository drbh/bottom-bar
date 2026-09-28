import AppKit
import SwiftUI

// MARK: - Bar View

struct BottomBarView: View {
    let items: [BottomBarItem]
    let rightItems: [BottomBarItem]
    @ObservedObject var state: BottomBarState
    let background: String?
    let borderColor: String?
    let onItemClick: (String, NSRect) -> Void

    private var backgroundColor: Color {
        guard let bg = background else { return Color.clear }
        if bg.lowercased() == "none" { return Color.clear }
        return Color(hex: bg) ?? Color.clear
    }

    private var topBorderColor: Color? {
        guard let bc = borderColor else { return Color.primary.opacity(0.15) }
        if bc.lowercased() == "none" { return nil }
        return Color(hex: bc) ?? Color.primary.opacity(0.15)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .allowsHitTesting(false)
                .overlay(alignment: .top) {
                    if let borderColor = topBorderColor {
                        Rectangle()
                            .fill(borderColor)
                            .frame(height: 0.5)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 0) {
                ForEach(items.map(\.id), id: \.self) { id in
                    if let item = items.first(where: { $0.id == id }) {
                        BarItemView(
                            item: item,
                            isActive: state.activeItemId == item.id,
                            onItemClick: onItemClick
                        )
                    }
                }
                Spacer().allowsHitTesting(false)
                ForEach(rightItems.map(\.id), id: \.self) { id in
                    if let item = rightItems.first(where: { $0.id == id }) {
                        BarItemView(
                            item: item,
                            isActive: state.activeItemId == item.id,
                            onItemClick: onItemClick
                        )
                    }
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Bar Item View (dispatches custom vs default)

struct BarItemView: View {
    let item: BottomBarItem
    let isActive: Bool
    let onItemClick: (String, NSRect) -> Void

    var body: some View {
        Group {
            if let customView = item.makeBarView() {
                // Custom inline view — no button chrome, no popover
                customView
            } else {
                BarItemButton(
                    item: item,
                    isActive: isActive,
                    onItemClick: onItemClick
                )
            }
        }
        .background(BarItemHitArea())
    }
}

// MARK: - Bar Item Button (default)

struct BarItemButton: View {
    let item: BottomBarItem
    let isActive: Bool
    let onItemClick: (String, NSRect) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: item.icon)
                .font(BarFont.regular(11))
            Text(item.title)
                .font(BarFont.regular(13))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
        )
        .onHover { isHovered = $0 }
        .overlay(ScreenFrameGrabber(id: item.id, onClick: { frame in
            onItemClick(item.id, frame)
        }))
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.white.opacity(0.3)
        } else if isHovered {
            return Color.white.opacity(0.15)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Panel Wrapper

struct PanelWrapperView: View {
    let arrowXOffset: CGFloat
    let panelWidth: CGFloat
    let innerContent: AnyView

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            innerContent
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThickMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.2), radius: 10, y: -2)

            // Arrow pointing down toward the bar
            Canvas { context, size in
                let cx = min(max(arrowXOffset, 12), panelWidth - 12)
                var path = Path()
                path.move(to: CGPoint(x: cx - 8, y: 0))
                path.addLine(to: CGPoint(x: cx, y: size.height))
                path.addLine(to: CGPoint(x: cx + 8, y: 0))
                path.closeSubpath()
                context.fill(path, with: .color(Color(nsColor: .windowBackgroundColor)))
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Click-Through Hosting View

/// Marker NSView inserted behind each bar item so we can identify
/// interactive regions during hit testing.
class BarItemMarker: NSView {}

struct BarItemHitArea: NSViewRepresentable {
    func makeNSView(context: Context) -> BarItemMarker { BarItemMarker() }
    func updateNSView(_ nsView: BarItemMarker, context: Context) {}
}

/// NSHostingView subclass that exposes hit-area checking for bar items.
/// The controller uses this to dynamically toggle `ignoresMouseEvents`
/// so clicks on empty areas pass through to windows below (e.g. the Dock).
class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    /// Returns true if `pointInWindow` lands within any bar item marker's bounds.
    func isOverBarItem(_ pointInWindow: NSPoint) -> Bool {
        let pointInView = convert(pointInWindow, from: nil)
        return hasMarkerAt(pointInView, in: self)
    }

    private func hasMarkerAt(_ point: NSPoint, in view: NSView) -> Bool {
        for subview in view.subviews {
            if subview is BarItemMarker {
                let local = subview.convert(point, from: self)
                if subview.bounds.contains(local) { return true }
            }
            if hasMarkerAt(point, in: subview) { return true }
        }
        return false
    }
}

// MARK: - Helpers

struct ScreenFrameGrabber: NSViewRepresentable {
    let id: String
    let onClick: (NSRect) -> Void

    func makeNSView(context: Context) -> ClickableNSView {
        let v = ClickableNSView()
        v.onClick = { nsView in
            guard let window = nsView.window else { return }
            let windowRect = nsView.convert(nsView.bounds, to: nil)
            let screenRect = NSRect(
                x: windowRect.origin.x + window.frame.origin.x,
                y: windowRect.origin.y + window.frame.origin.y,
                width: windowRect.width,
                height: windowRect.height
            )
            onClick(screenRect)
        }
        return v
    }

    func updateNSView(_ nsView: ClickableNSView, context: Context) {}
}

class ClickableNSView: NSView {
    var onClick: ((NSView) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?(self)
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Hex Color Parsing

extension Color {
    /// Parses a hex color string like "#FF0000", "#ff0000", or "FF0000".
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }

        guard s.count == 6 || s.count == 8 else { return nil }
        guard let value = UInt64(s, radix: 16) else { return nil }

        if s.count == 6 {
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b)
        } else {
            let r = Double((value >> 24) & 0xFF) / 255.0
            let g = Double((value >> 16) & 0xFF) / 255.0
            let b = Double((value >> 8) & 0xFF) / 255.0
            let a = Double(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, opacity: a)
        }
    }
}
