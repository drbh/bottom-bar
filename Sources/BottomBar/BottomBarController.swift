import AppKit
import SwiftUI

/// Observable state shared between the controller and the bar view.
/// This lets us update the active item highlight without replacing
/// the entire NSHostingView (which would destroy @StateObject state).
class BottomBarState: ObservableObject {
    @Published var activeItemId: String? = nil
}

/// Manages the bottom bar window and popover panels.
class BottomBarController {
    static let barHeight: CGFloat = 24
    static let arrowHeight: CGFloat = 8

    private var barWindow: NSWindow!
    private var allItems: [BottomBarItem] = []
    private var openPanels: [String: NSWindow] = [:]
    private let state = BottomBarState()
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private var items: [BottomBarItem] {
        allItems.filter { $0.side == "left" }
    }

    private var rightItems: [BottomBarItem] {
        allItems.filter { $0.side == "right" }
    }

    init(items: [BottomBarItem]) {
        self.allItems = items
    }

    func addItem(_ item: BottomBarItem) {
        allItems.append(item)
        rebuildBarContent()
    }

    func removeItem(id: String) {
        allItems.removeAll { $0.id == id }
        dismissPanel(id: id)
        rebuildBarContent()
    }

    /// Replace all plugin-loaded items (called by PluginManager on hot-reload).
    func replacePluginItems(_ newItems: [BottomBarItem]) {
        let oldIds = Set(allItems.map(\.id))
        let newIds = Set(newItems.map(\.id))
        for id in oldIds.subtracting(newIds) {
            dismissPanel(id: id)
        }
        allItems = newItems
        rebuildBarContent()
    }

    func show() {
        guard let screen = NSScreen.main else { return }

        let barFrame = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y,
            width: screen.frame.width,
            height: Self.barHeight
        )

        barWindow = NSWindow(
            contentRect: barFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        barWindow.level = .statusBar
        barWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        barWindow.isOpaque = false
        barWindow.backgroundColor = .clear
        barWindow.hasShadow = false
        barWindow.ignoresMouseEvents = false

        rebuildBarContent()
        barWindow.orderFrontRegardless()
        installEventMonitors()
    }

    // MARK: - Private

    private func rebuildBarContent() {
        guard barWindow != nil else { return }
        let view = BottomBarView(
            items: items,
            rightItems: rightItems,
            state: state,
            onItemClick: { [weak self] itemId, frame in
                self?.togglePanel(for: itemId, relativeTo: frame)
            }
        )
        barWindow.contentView = NSHostingView(rootView: view)
    }

    private func togglePanel(for itemId: String, relativeTo buttonFrame: NSRect) {
        if openPanels[itemId] != nil {
            dismissAllPanels()
            return
        }

        for key in openPanels.keys { dismissPanel(id: key) }

        let allItems = items + rightItems
        guard let item = allItems.first(where: { $0.id == itemId }),
              let screen = NSScreen.main else { return }

        // Only update state — don't rebuild the hosting view
        state.activeItemId = itemId

        let size = item.panelSize
        guard size != .zero else { return }

        let panelWidth = size.width
        let innerContent = item.makeContent(close: { [weak self] in
            self?.dismissAllPanels()
        })

        // Build the full panel view
        // Use a temporary x position; we'll set the real frame after measuring
        let arrowXGuess = buttonFrame.midX - (buttonFrame.midX - panelWidth / 2)

        let wrapperView = PanelWrapperView(
            arrowXOffset: arrowXGuess,
            panelWidth: panelWidth,
            innerContent: innerContent
        )

        let hostingView = NSHostingView(rootView: wrapperView)
        // Give it the target width so it can compute height
        hostingView.frame.size.width = panelWidth
        hostingView.layoutSubtreeIfNeeded()
        let measuredHeight = hostingView.fittingSize.height
        let contentHeight = measuredHeight > 0 ? measuredHeight : (size.height + Self.arrowHeight)

        // Panel sits just above the bottom bar
        let panelY = screen.frame.origin.y + Self.barHeight + 1
        let maxHeight = screen.visibleFrame.maxY - panelY
        let clampedHeight = min(contentHeight, maxHeight)

        let panelX = min(
            max(buttonFrame.midX - panelWidth / 2, screen.frame.origin.x + 4),
            screen.frame.origin.x + screen.frame.width - panelWidth - 4
        )

        let panelFrame = NSRect(x: panelX, y: panelY, width: panelWidth, height: clampedHeight)

        let panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        // Recompute arrow position with actual panel frame
        let arrowRelativeX = buttonFrame.midX - panelFrame.origin.x

        // Rebuild with correct arrow offset
        let finalContent = PanelWrapperView(
            arrowXOffset: arrowRelativeX,
            panelWidth: panelWidth,
            innerContent: innerContent
        )

        panel.contentView = NSHostingView(rootView: finalContent)
        panel.orderFrontRegardless()
        openPanels[itemId] = panel
    }

    private func dismissAllPanels() {
        for key in openPanels.keys { dismissPanel(id: key) }
        state.activeItemId = nil
    }

    private func dismissPanel(id: String) {
        openPanels[id]?.orderOut(nil)
        openPanels.removeValue(forKey: id)
    }

    private func handleClickAt(_ screenPoint: NSPoint) {
        guard !openPanels.isEmpty else { return }

        let barFrame = barWindow.frame
        if barFrame.contains(screenPoint) { return }

        for (_, panel) in openPanels {
            if panel.frame.contains(screenPoint) { return }
        }

        dismissAllPanels()
    }

    private func installEventMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, !self.openPanels.isEmpty else { return event }

            let screenPoint: NSPoint
            if let eventWindow = event.window {
                screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
            } else {
                screenPoint = event.locationInWindow
            }

            self.handleClickAt(screenPoint)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.dismissAllPanels()
        }
    }
}
