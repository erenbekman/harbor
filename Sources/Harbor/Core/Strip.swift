import AppKit
import Combine
import SwiftUI

/// The edge strip: the only surface that belongs to no window, which is the
/// point — you want to see what is running while you are in the editor, not in
/// Harbor. It sits as a sliver on the right edge and opens when the pointer
/// reaches it.
@MainActor
final class Strip: ObservableObject {
    /// The card floats clear of the screen edge; the WINDOW still reaches it, so
    /// the pointer thrown at the edge opens the strip.
    static let edgeInset: CGFloat = 10
    static let tileSize: CGFloat = 54
    static let tileSpacing: CGFloat = 8
    static let railInset: CGFloat = 8
    static let tileCorner: CGFloat = 16
    static let railCorner: CGFloat = 22
    static let cardWidth: CGFloat = 236
    static let cardCorner: CGFloat = 14
    static let tailWidth: CGFloat = 8
    static let tailHeight: CGFloat = 16
    static let cardPadding: CGFloat = 8
    static let headerHeight: CGFloat = 30
    static let serviceHeight: CGFloat = 38
    static var railWidth: CGFloat { tileSize + railInset * 2 }

    @Published private(set) var installed = false
    @Published private(set) var open = false
    @Published private(set) var focus: UUID?
    /// Where the strip sits on the right edge, as a fraction of the screen, so
    /// it keeps its place when the panel grows or the display changes.
    private var centerFraction: CGFloat =
        UserDefaults.standard.object(forKey: "stripCenter") as? Double ?? 0.5

    var onOpenProject: ((Project) -> Void)?

    private let store: Store
    private let runner: Runner
    private var panel: StripPanel?
    private var hideTask: Task<Void, Never>?
    private var watch: AnyCancellable?

    init(store: Store, runner: Runner) {
        self.store = store
        self.runner = runner
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "stripEnabled") as? Bool ?? true
    }

    /// The one place the preference and the panel are kept in step — the menu
    /// bar item and Settings both come through here.
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "stripEnabled")
        if enabled { install() } else { remove() }
    }

    func install() {
        guard panel == nil else { return }

        let hosting = FirstMouseHostingView(rootView: AnyView(
            StripView(strip: self).environmentObject(store).environmentObject(runner)
        ))
        hosting.autoresizingMask = [.width, .height]

        let container = HoverView()
        container.onEnter = { [weak self] point, size in
            self?.pointerMoved(to: point, in: size)
            self?.hoverBegan()
        }
        container.onMove = { [weak self] point, size in self?.pointerMoved(to: point, in: size) }
        container.onExit = { [weak self] in self?.hoverEnded() }
        hosting.frame = container.bounds
        container.addSubview(hosting)

        let panel = StripPanel(contentRect: frame(open: false),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The window is wider than the card it draws, and AppKit's own shadow is
        // computed from the window's alpha ONCE — it goes stale on every resize,
        // and this panel resizes every time it opens. SwiftUI draws it instead.
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.orderFrontRegardless()
        self.panel = panel
        installed = true

        // Adding or removing a project changes the height the panel must have,
        // and `objectWillChange` fires BEFORE the change lands.
        watch = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.layout() }
        }
    }

    func remove() {
        watch = nil
        hideTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
        open = false
        installed = false
    }

    func openInWindow(_ project: Project) {
        setOpen(false)
        onOpenProject?(project)
    }

    // MARK: - Moving

    /// Dragged by its grip; `delta` is in screen points, positive upwards.
    func move(by delta: CGFloat) {
        guard let panel, let visible = (panel.screen ?? NSScreen.main)?.visibleFrame,
              visible.height > 0 else { return }
        let height = panel.frame.height
        let lowest = visible.minY + height / 2
        let highest = visible.maxY - height / 2
        let current = visible.minY + centerFraction * visible.height
        let wanted = min(max(current + delta, min(lowest, highest)), max(lowest, highest))
        centerFraction = (wanted - visible.minY) / visible.height
        panel.setFrame(frame(open: open), display: true)
    }

    func rememberPosition() {
        UserDefaults.standard.set(Double(centerFraction), forKey: "stripCenter")
    }

    // MARK: - Hover

    private func hoverBegan() {
        hideTask?.cancel()
        setOpen(true)
    }

    private func hoverEnded() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.setOpen(false)
        }
    }

    private func setOpen(_ value: Bool) {
        guard open != value else { return }
        open = value
        layout()
    }

    // MARK: - Geometry

    var focusProject: Project? {
        store.projects.first { $0.id == focus } ?? store.projects.first
    }

    /// Heights are ARITHMETIC: AppKit animates the window frame and has to know
    /// the total before SwiftUI lays anything out.
    private var railHeight: CGFloat {
        let count = CGFloat(max(store.projects.count, 1))
        return Self.railInset * 2 + count * Self.tileSize + (count - 1) * Self.tileSpacing
    }

    private func cardHeight(_ project: Project) -> CGFloat {
        Self.cardPadding * 2 + Self.headerHeight
            + CGFloat(max(project.services.count, 1)) * Self.serviceHeight
    }

    private var ceiling: CGFloat {
        ((panel?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800) - 24
    }

    private func panelHeight(open: Bool) -> CGFloat {
        guard open, let project = focusProject else { return min(railHeight, ceiling) }
        return min(max(railHeight, cardHeight(project)), ceiling)
    }

    var tailCenter: CGFloat {
        guard let project = focusProject,
              let index = store.projects.firstIndex(where: { $0.id == project.id })
        else { return Self.tileSize / 2 }
        let height = panelHeight(open: true)
        let railTop = (height - railHeight) / 2
        let tile = railTop + Self.railInset
            + CGFloat(index) * (Self.tileSize + Self.tileSpacing) + Self.tileSize / 2
        return tile - (height - cardHeight(project)) / 2
    }

    private func pointerMoved(to point: NSPoint, in size: NSSize) {
        guard !store.projects.isEmpty else { return }
        guard point.x >= size.width - Self.edgeInset - Self.railWidth else { return }
        let fromTop = (size.height + railHeight) / 2 - point.y
        let step = Self.tileSize + Self.tileSpacing
        let raw = Int(((fromTop - Self.railInset) / step).rounded(.down))
        let id = store.projects[min(max(raw, 0), store.projects.count - 1)].id
        guard focus != id else { return }
        focus = id
        if open { layout() }
    }

    private func frame(open: Bool) -> NSRect {
        let screen = panel?.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }
        let card = open && focusProject != nil ? Self.cardWidth + Self.tailWidth : 0
        let width = card + Self.railWidth + Self.edgeInset
        let height = panelHeight(open: open)
        let center = visible.minY + centerFraction * visible.height
        let clamped = min(max(center, visible.minY + height / 2), visible.maxY - height / 2)
        return NSRect(x: visible.maxX - width,
                      y: clamped - height / 2,
                      width: width, height: height)
    }

    private func layout() {
        guard let panel else { return }
        let target = frame(open: open)
        guard target != panel.frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
    }
}

final class StripPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A panel that is never key would otherwise spend the first click on trying to
/// activate itself, and the button under the pointer would not fire.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// `.activeAlways`, never SwiftUI's `onHover`: the panel is never key, and the
/// only time the strip matters is when another application is in front.
final class HoverView: NSView {
    var onEnter: ((NSPoint, NSSize) -> Void)?
    var onMove: ((NSPoint, NSSize) -> Void)?
    var onExit: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved,
                                            .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?(location(of: event), bounds.size) }
    override func mouseMoved(with event: NSEvent) { onMove?(location(of: event), bounds.size) }
    override func mouseExited(with event: NSEvent) { onExit?() }

    private func location(of event: NSEvent) -> NSPoint {
        convert(event.locationInWindow, from: nil)
    }
}
