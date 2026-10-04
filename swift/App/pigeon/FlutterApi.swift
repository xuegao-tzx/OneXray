import Foundation
#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#else
#error("Unsupported platform.")
#endif

@MainActor
class AppFlutterApi {
    private let flutterApi: BridgeFlutterApi
    init(binaryMessenger: FlutterBinaryMessenger) {
        self.flutterApi = BridgeFlutterApi(binaryMessenger: binaryMessenger)
        VPNManager.shared.registerStatusObserver(vpnStatusChanged)
    }

    deinit {
        Task {
            await VPNManager.shared.unregisterStatusObserver()
        }
    }

    func vpnStatusChanged() async throws {
        let status = try await VPNManager.shared.readVpnStatus()
        flutterApi.vpnStatusChanged(status: status) { _ in }
    }

    //macOS menu bar=================
    func listMenuServers() async throws -> [MenuServerItem] {
        try await withCheckedThrowingContinuation { continuation in
            flutterApi.listMenuServers { result in
                continuation.resume(with: result)
            }
        }
    }

    func speedTestMenuServers() async throws -> [MenuServerItem] {
        try await withCheckedThrowingContinuation { continuation in
            flutterApi.speedTestMenuServers { result in
                continuation.resume(with: result)
            }
        }
    }

    func selectMenuServer(id: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            flutterApi.selectMenuServer(id: id) { result in
                continuation.resume(with: result)
            }
        }
    }
}
