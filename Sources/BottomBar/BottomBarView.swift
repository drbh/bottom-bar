import AppKit
import SwiftUI

// MARK: - Bar View

struct BottomBarView: View {
    let items: [BottomBarItem]
    let rightItems: [BottomBarItem]
    @ObservedObject var state: BottomBarState
    let onItemClick: (String, NSRect) -> Void

    var body: some View {
        ZStack {
            Color.clear
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(height: 0.5)
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
                Spacer()
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            // Arrow pointing down toward the bar, aligned to the button
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
