import SwiftUI
import WidgetKit

/// Entry point of the macOS Control Center extension. The control itself lives
/// in `swift/All/ProxyControlWidget.swift` so iOS and macOS share one behavior.
///
/// A `WidgetBundle` holds widgets, not other bundles, so the control is listed
/// directly. The target deploys to macOS 26 because that is where
/// `ControlWidget` exists; the containing App keeps its lower target, so the
/// extension is simply unavailable on older systems.
@main
@available(macOS 26.0, *)
struct OneXrayControlExtension: WidgetBundle {
    var body: some Widget {
        ProxyControlWidget()
    }
}
