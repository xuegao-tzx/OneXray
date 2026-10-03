#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// Menu bar extra for the proxy.
///
/// The on/off item is handled natively through `QuickControl`, exactly like the
/// Android quick settings tile, so it keeps working while the Flutter window is
/// hidden. The server list and speed test are business rules owned by the Dart
/// service layer, so those items go back over the Pigeon bridge instead of
/// duplicating the model in Swift.
@MainActor
final class MenuBarController: NSObject, ObservableObject {
    /// The App creates the instance; the Flutter window attaches its channel.
    static weak var shared: MenuBarController?

    @Published private(set) var status: QuickControlStatus = .disconnected
    @Published private(set) var notice: String?
    @Published private(set) var busy = false
    @Published private(set) var servers: [MenuServer] = []
    @Published private(set) var lastError: String?

    private var statusItem: NSStatusItem?
    private var poll: Task<Void, Never>?
    private weak var bridge: AppFlutterApi?

    struct MenuServer: Identifiable, Equatable {
        let id: String
        let remark: String
        let isCurrent: Bool
        let delay: Int64?
    }

    func attach(to flutterApi: AppFlutterApi?) {
        bridge = flutterApi
    }

    func install() {
        Self.shared = self
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "shield.lefthalf.filled",
            accessibilityDescription: "OneXray"
        )
        item.button?.image?.isTemplate = true
        item.menu = NSMenu()
        item.menu?.delegate = self
        statusItem = item
        Task { await refresh() }
        startPolling()
    }

    private func startPolling() {
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func refresh() async {
        let current = await QuickControl.status()
        if current != status {
            status = current
            NSApp.dockTile.badgeLabel = current.isOn ? "ON" : nil
        }
        if statusItem?.menu?.numberOfItems ?? 0 > 0 {
            rebuild()
        }
    }

    func toggle() async {
        busy = true
        defer { busy = false }
        let outcome = await QuickControl.toggle()
        switch outcome {
        case .applied:
            notice = nil
        case .needsApp(let reason), .failed(let reason):
            notice = reason
        }
        await refresh()
    }

    func loadServers() async {
        guard let bridge else { return }
        do {
            let items = try await bridge.listMenuServers()
            servers = items.map {
                MenuServer(id: $0.id, remark: $0.remark, isCurrent: $0.isCurrent, delay: $0.delay)
            }
        } catch {
            lastError = error.localizedDescription
        }
        rebuild()
    }

    func select(_ server: MenuServer) async {
        guard let bridge else { return }
        do {
            try await bridge.selectMenuServer(id: server.id)
            await loadServers()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func runSpeedTest() async {
        guard let bridge else { return }
        busy = true
        defer { busy = false }
        do {
            let items = try await bridge.speedTestMenuServers()
            servers = items.map {
                MenuServer(id: $0.id, remark: $0.remark, isCurrent: $0.isCurrent, delay: $0.delay)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        rebuild()
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showMainWindow:")), to: nil, from: nil)
    }

    // MARK: - Menu construction

    private func rebuild() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let title = NSMenuItem(title: statusLabel, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: status.isOn ? "Stop Proxy" : "Start Proxy",
            action: #selector(handleToggle),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.isEnabled = !busy
        menu.addItem(toggleItem)

        if let notice {
            let noticeItem = NSMenuItem(title: notice, action: nil, keyEquivalent: "")
            noticeItem.isEnabled = false
            menu.addItem(.separator())
            menu.addItem(noticeItem)
        }
        menu.addItem(.separator())

        let serversItem = NSMenuItem(title: "Servers", action: nil, keyEquivalent: "")
        let serversMenu = NSMenu()
        if servers.isEmpty {
            let empty = NSMenuItem(title: "Open OneXray to load servers", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            serversMenu.addItem(empty)
        } else {
            for server in servers {
                let item = NSMenuItem(
                    title: Self.title(for: server),
                    action: #selector(handleSelectServer(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = server.id
                item.state = server.isCurrent ? .on : .off
                serversMenu.addItem(item)
            }
        }
        serversItem.submenu = serversMenu
        menu.addItem(serversItem)

        let speedItem = NSMenuItem(
            title: busy ? "Testing…" : "Speed Test",
            action: #selector(handleSpeedTest),
            keyEquivalent: ""
        )
        speedItem.target = self
        speedItem.isEnabled = !busy
        menu.addItem(speedItem)
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open OneXray", action: #selector(handleOpen), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
    }

    private var statusLabel: String {
        switch status {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .disconnected: return "Disconnected"
        }
    }

    private static func title(for server: MenuServer) -> String {
        guard let delay = server.delay, delay > 0 else { return server.remark }
        return "\(server.remark) — \(delay) ms"
    }

    // MARK: - Actions

    @objc private func handleToggle() {
        Task { await toggle() }
    }

    @objc private func handleSpeedTest() {
        Task { await runSpeedTest() }
    }

    @objc private func handleSelectServer(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let server = servers.first(where: { $0.id == id }) else { return }
        Task { await select(server) }
    }

    @objc private func handleOpen() {
        openMainWindow()
    }
}

extension MenuBarController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            Task { await self.loadServers() }
        }
    }
}
#endif
