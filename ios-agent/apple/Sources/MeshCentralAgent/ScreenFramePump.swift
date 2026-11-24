// SPDX-License-Identifier: Apache-2.0
import Foundation
import CoreGraphics
import CoreImage
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

/// One capture/encode/send in flight, adaptive 1..3 fps, no on-disk media.
public final class ScreenFramePump {
    public let id = UUID()
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "MeshCentral.jpeg")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private weak var relay: DesktopRelay?
    private var active = true
    private var busy = false
    private var lastFrame = -Double.infinity
    public init(relay: DesktopRelay) { self.relay = relay }
    public func stop() { lock.lock(); active = false; lock.unlock() }
    private func reserve() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        guard active, !busy, now - lastFrame >= (relay?.videoProfile().interval ?? 1) else { return false }
        busy = true; lastFrame = now; return true
    }
    private func release() { lock.lock(); busy = false; lock.unlock() }
    private var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }

    public func submit(image: CGImage) {
        guard reserve() else { return }
        queue.async { autoreleasepool { self.encode(CIImage(cgImage: image)) } }
    }
    public func submit(sample: CMSampleBuffer, orientation: CGImagePropertyOrientation) {
        guard CMSampleBufferDataIsReady(sample), reserve() else { return }
        queue.async {
            autoreleasepool {
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { self.release(); return }
                self.encode(CIImage(cvPixelBuffer: buffer).oriented(orientation))
            }
        }
    }
    private func encode(_ input: CIImage) {
        guard isActive, let relay = relay else { release(); return }
        let rect = input.extent
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0,
              rect.width <= 8192, rect.height <= 8192 else { release(); return }
        let profile = relay.videoProfile()
        let scale = min(1, profile.longSide / max(rect.width, rect.height), profile.shortSide / min(rect.width, rect.height))
        let image = input.transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = CGRect(x: 0, y: 0, width: floor(rect.width * scale), height: floor(rect.height * scale))
        guard bounds.width >= 1, bounds.height >= 1, let cg = context.createCGImage(image, from: bounds), isActive else { release(); return }
        guard let bytes = Self.jpeg(cg, quality: profile.quality), isActive else { release(); return }
        relay.submit(jpeg: bytes, width: UInt16(cg.width), height: UInt16(cg.height), source: id) { [weak self] in self?.release() }
    }

    // Generated independently of ReplayKit so even a stock Desktop viewer
    // replaces its last live image with pixels unrelated to the device.
    static func privacyImage() -> Data? {
        guard let frame = CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        frame.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        frame.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        return frame.makeImage().flatMap { jpeg($0, quality: 0.5) }
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination), bytes.length <= 524288 else { return nil }
        return bytes as Data
    }
}
