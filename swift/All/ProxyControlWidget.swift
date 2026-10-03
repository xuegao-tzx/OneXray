#if canImport(WidgetKit) && canImport(AppIntents)
import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / menu bar control that turns the saved proxy configuration
/// on and off. It is shared by the iOS and macOS widget extensions, so it only
/// depends on `QuickControl` and never on the Flutter engine.
///
/// Note: this SDK has no `ControlWidgetBundle`; a plain `WidgetBundle` accepts
/// `ControlWidget` entries directly. The `@main` bundle lives with each
/// extension target.
@available(iOS 18.0, macOS 26.0, *)
struct SetProxyEnabledIntent: SetValueIntent {
    static var title: LocalizedStringResource { "OneXray Proxy" }
    static var description: IntentDescription {
        "Turn the saved OneXray proxy configuration on or off."
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Enabled") var value: Bool

    init() {}

    init(value: Bool) { self.value = value }

    func perform() async throws -> some IntentResult {
        let outcome = await QuickControl.toggle()
        switch outcome {
        case .applied(let status):
            // Keep the rendered value honest when the system refused to move.
            if status.isOn != value {
                throw QuickControlError.unavailable(
                    "OneXray could not turn \(value ? "on" : "off")."
                )
            }
            return .result()
        case .needsApp(let reason):
            throw QuickControlError.unavailable(reason)
        case .failed(let reason):
            throw QuickControlError.unavailable(reason)
        }
    }
}

@available(iOS 18.0, macOS 26.0, *)
struct ProxyControlValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        await QuickControl.status().isOn
    }
}

@available(iOS 18.0, macOS 26.0, *)
struct ProxyControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "ink.xcl.onexray.proxy",
            provider: ProxyControlValueProvider()
        ) { isOn in
            ControlWidgetToggle(isOn: isOn, action: SetProxyEnabledIntent(value: isOn)) {
                Label("OneXray", systemImage: isOn ? "shield.lefthalf.filled" : "shield")
            } valueLabel: { isOn in
                Text(isOn ? "On" : "Off")
            }
        }
    }
}
#endif
