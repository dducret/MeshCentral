// SPDX-License-Identifier: Apache-2.0
import UIKit

/// Explicitly restricted to the app's own simulator window. No system screenshot API.
@MainActor
final class SimulatorCapture {
    private var timer: Timer?
    private var pump: ScreenFramePump?
    func start(relay: DesktopRelay) {
        #if targetEnvironment(simulator)
        let pump = ScreenFramePump(relay: relay)
        relay.captureStarted(source: pump.id) // Local approval already happened; this is our app view.
        resume(pump)
        #endif
    }
    func resume(_ pump: ScreenFramePump?) {
        #if targetEnvironment(simulator)
        stop()
        guard let pump else { return }
        self.pump = pump
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.capture() }
        }
        #endif
    }
    private func capture() {
        #if targetEnvironment(simulator)
        guard UIApplication.shared.applicationState == .active,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow), window.bounds.width > 0 else { return }
        let size = window.bounds.size
        let ratio = min(1, 720 / size.width, 1280 / size.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        var drawn = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: size.width * ratio, height: size.height * ratio), format: format).image { context in
            context.cgContext.scaleBy(x: ratio, y: ratio)
            drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        if drawn, let cg = image.cgImage { pump?.submit(image: cg) }
        #endif
    }
    func stop() { timer?.invalidate(); timer = nil; pump?.stop(); pump = nil }
}
