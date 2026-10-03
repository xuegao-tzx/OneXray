import Foundation
import NetworkExtension

/// Proxy state as seen by a control surface. Deliberately separate from the
/// Pigeon `VpnStatus` so this file stays free of generated bridge types and can
/// be compiled into widget extensions that do not link the Flutter App target.
public enum QuickControlStatus: String, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting

    public var isOn: Bool { self == .connected || self == .connecting }
}

public enum QuickControlOutcome: Equatable, Sendable {
    /// The system accepted the command. `status` is the state observed after it.
    case applied(QuickControlStatus)
    /// The control cannot act on its own; the App has to run once first.
    case needsApp(String)
    /// The system refused the command.
    case failed(String)
}

/// Control Center surfaces render this as an alert, so the message has to say
/// what the person should do next rather than expose an internal error.
public enum QuickControlError: LocalizedError, Sendable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        }
    }
}

/// Lean proxy control for surfaces that run without the Flutter engine, such as
/// Control Center controls and widget extensions.
///
/// It follows the same saved-configuration contract as the Android quick
/// settings tile: the App Group `run/start.json` is the single source of truth,
/// so a control toggled outside the App starts exactly the configuration the
/// App last persisted. No second configuration or VPN-state cache is kept here.
public enum QuickControl {

    public static func status() async -> QuickControlStatus {
        guard let manager = await loadManager() else { return .disconnected }
        return map(manager.connection.status)
    }

    public static func toggle() async -> QuickControlOutcome {
        let current = await status()
        switch current {
        case .connected, .disconnecting:
            return await stop()
        case .disconnected, .connecting:
            return await start()
        }
    }

    public static func start() async -> QuickControlOutcome {
        guard Constants.useSystemExtension == false else {
            return .needsApp("The system extension build manages the Core from the App.")
        }
        guard let request = StartVpnRequest.startModel else {
            return .needsApp("Open OneXray and connect once to save a configuration.")
        }
        do {
            guard let manager = await loadManager() else {
                return .needsApp("Allow the VPN configuration in OneXray first.")
            }
            try await apply(request: request, to: manager)
            guard let session = manager.connection as? NETunnelProviderSession else {
                return .failed("The VPN session is not ready.")
            }
            try session.startTunnel()
            return .applied(await status())
        } catch {
            YGLog("QuickControl start failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    public static func stop() async -> QuickControlOutcome {
        do {
            guard let manager = await loadManager() else {
                // Nothing configured: the tunnel is already down.
                return .applied(.disconnected)
            }
            try await apply(request: StartVpnRequest(tun: TunJson()), to: manager)
            guard let session = manager.connection as? NETunnelProviderSession else {
                return .applied(.disconnected)
            }
            session.stopTunnel()
            return .applied(await status())
        } catch {
            YGLog("QuickControl stop failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Manager loading

    private static func loadManager() async -> NETunnelProviderManager? {
        try? await NETunnelProviderManager.loadAllFromPreferences()
            .first { manager in
                guard let conf = manager.protocolConfiguration as? NETunnelProviderProtocol else {
                    return false
                }
                return conf.providerBundleIdentifier == packetTunnelId()
            }
    }

    // MARK: - Configuration persistence

    /// Writes the pending request into the system VPN profile before the tunnel
    /// starts, mirroring the App's own start path. The tunnel extension reads
    /// this provider configuration, not the App Group file, once it is running.
    private static func apply(request: StartVpnRequest, to manager: NETunnelProviderManager) async throws {
        let tun = request.tun ?? TunJson()
        manager.isEnabled = true
        if let conf = manager.protocolConfiguration as? NETunnelProviderProtocol {
            applyRouting(tun, to: conf)
            var providerConfig = conf.providerConfiguration ?? [:]
            if let encoded = try? JsonTool.encode(request) {
                providerConfig["request"] = encoded
            }
            conf.providerConfiguration = providerConfig
        }
        if let onDemand = tun.onDemandEnabled, onDemand {
            let rules = convertRules(tun.onDemandRules ?? [])
            manager.isOnDemandEnabled = !rules.isEmpty
            manager.onDemandRules = rules.isEmpty ? [NEOnDemandRuleConnect()] : rules
        } else {
            manager.isOnDemandEnabled = false
            manager.onDemandRules = nil
        }
        manager.protocolConfiguration?.disconnectOnSleep = false
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
    }

    private static func applyRouting(_ tun: TunJson, to conf: NETunnelProviderProtocol) {
        conf.includeAllNetworks = tun.includeAllNetworks ?? false
        conf.excludeLocalNetworks = tun.excludeLocalNetworks ?? true
        if #available(macOS 13.3, iOS 16.4, *) {
            conf.excludeCellularServices = tun.excludeCellularServices ?? true
            conf.excludeAPNs = tun.excludeAPNs ?? true
        }
        if #available(macOS 14.4, iOS 17.4, *) {
            conf.excludeDeviceCommunication = tun.excludeDeviceCommunication ?? true
        }
    }

    private static func convertRules(_ rules: [OnDemandRule]) -> [NEOnDemandRule] {
        rules.compactMap { rule in
            guard let mode = rule.mode else { return nil }
            let converted: NEOnDemandRule
            switch mode {
            case .connect: converted = NEOnDemandRuleConnect()
            case .disconnect: converted = NEOnDemandRuleDisconnect()
            case .ignore: converted = NEOnDemandRuleIgnore()
            }
            guard let interfaceType = rule.interfaceType,
                  let match = convertInterfaceType(interfaceType) else { return nil }
            converted.interfaceTypeMatch = match
            if match == .wiFi, let ssid = rule.ssid, !ssid.isEmpty {
                converted.ssidMatch = ssid
            }
            return converted
        }
    }

    private static func convertInterfaceType(
        _ interfaceType: OnDemandRuleInterfaceType
    ) -> NEOnDemandRuleInterfaceType? {
        switch interfaceType {
        case .any: return .any
        case .wifi: return .wiFi
        #if os(macOS)
        case .ethernet: return .ethernet
        case .cellular: return nil
        #else
        case .cellular: return .cellular
        case .ethernet: return nil
        #endif
        }
    }

    private static func map(_ status: NEVPNStatus) -> QuickControlStatus {
        switch status {
        case .connected: return .connected
        case .connecting, .reasserting: return .connecting
        case .disconnecting: return .disconnecting
        default: return .disconnected
        }
    }
}
