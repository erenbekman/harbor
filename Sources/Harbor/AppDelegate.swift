import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store()
    private let runner = Runner()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var palette: PaletteWindow?
    private var settings: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Tmux.ensureConfig()
        runner.store = store
        runner.startPolling()
        buildMainMenu()
        buildStatusItem()
        showWindow(nil)
        runner.startAutoServices()
        HotKey.register()
        HotKey.onPress = { [weak self] in self?.togglePalette(nil) }
        Updater.shared.check(silent: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return true
    }

    // MARK: - Window

    @objc func showWindow(_ sender: Any?) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = RootView()
            .environmentObject(store)
            .environmentObject(runner)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Harbor"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        window.center()
        window.setFrameAutosaveName("HarborMain")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Quick switcher

    @objc func togglePalette(_ sender: Any?) {
        if let palette, palette.isVisible {
            closePalette()
            return
        }
        let view = PaletteView(close: { [weak self] in self?.closePalette() },
                               reveal: { [weak self] project in
                                   self?.store.selection = project.id
                                   self?.showWindow(nil)
                               })
            .environmentObject(store)
            .environmentObject(runner)

        let panel = PaletteWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: view)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 280, y: frame.midY + 60))
        }
        palette = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func closePalette() {
        palette?.orderOut(nil)
        palette = nil
    }

    @objc func showSettings(_ sender: Any?) {
        if let settings {
            settings.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        settings = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        Updater.shared.check()
        showSettings(nil)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Notify.post(title: "Harbor", message: "Could not change the login item: \(error.localizedDescription)")
        }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sailboat.fill", accessibilityDescription: "Harbor")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if store.projects.isEmpty {
            let empty = NSMenuItem(title: "No projects yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for project in store.projects {
            let header = NSMenuItem(title: project.name, action: nil, keyEquivalent: "")
            header.attributedTitle = NSAttributedString(
                string: project.name,
                attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                             .foregroundColor: NSColor.secondaryLabelColor])
            menu.addItem(header)

            if project.services.isEmpty {
                let none = NSMenuItem(title: "   no services", action: nil, keyEquivalent: "")
                none.isEnabled = false
                menu.addItem(none)
            }
            for service in project.services {
                let status = runner.status(of: service)
                let port = runner.port(of: service)
                let item = NSMenuItem(title: "\(service.name) — \(status.label(port: port))",
                                      action: #selector(toggleService(_:)), keyEquivalent: "")
                item.target = self
                item.image = Self.dot(NSColor(status.color))
                item.representedObject = ServiceRef(project: project.id, service: service.id)
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let open = NSMenuItem(title: "Open Harbor", action: #selector(showWindow(_:)), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let switcher = NSMenuItem(title: "Quick Switcher  ⌃⌘H", action: #selector(togglePalette(_:)),
                                  keyEquivalent: "")
        switcher.target = self
        menu.addItem(switcher)
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if let version = Updater.shared.availableVersion {
            let update = NSMenuItem(title: "Update to \(version)…", action: #selector(checkForUpdates(_:)),
                                    keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit Harbor", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private struct ServiceRef {
        let project: UUID
        let service: UUID
    }

    @objc private func toggleService(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? ServiceRef,
              let project = store.projects.first(where: { $0.id == ref.project }),
              let service = project.services.first(where: { $0.id == ref.service })
        else { return }
        runner.toggle(service, in: project)
    }

    private static func dot(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 9, height: 9)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    // MARK: - Main menu

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "About Harbor", action: #selector(showSettings(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates(_:)),
                                 keyEquivalent: "")
        updates.target = self
        appMenu.addItem(updates)
        appMenu.addItem(.separator())
        let settingsMenuItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)),
                                          keyEquivalent: ",")
        settingsMenuItem.target = self
        appMenu.addItem(settingsMenuItem)
        appMenu.addItem(.separator())
        let openItem = NSMenuItem(title: "Open Harbor", action: #selector(showWindow(_:)), keyEquivalent: "0")
        openItem.target = self
        appMenu.addItem(openItem)
        let paletteItem = NSMenuItem(title: "Quick Switcher", action: #selector(togglePalette(_:)),
                                     keyEquivalent: "k")
        paletteItem.target = self
        appMenu.addItem(paletteItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Harbor", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Harbor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
