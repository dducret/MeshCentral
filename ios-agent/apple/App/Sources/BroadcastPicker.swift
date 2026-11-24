// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import ReplayKit

struct BroadcastPicker: UIViewRepresentable {
    static func validateEmbeddedExtension() throws {
        guard let directory = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
              let extensionBundle = items.lazy.filter({ $0.pathExtension == "appex" })
                .compactMap({ Bundle(url: $0) }).first(where: { $0.bundleIdentifier == BroadcastChannel.extensionID }) else {
            throw BroadcastConfigurationError.extensionMissing
        }
        let declaration = extensionBundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any]
        let appGroup = Bundle.main.object(forInfoDictionaryKey: "MeshCentralAppGroup") as? String
        guard extensionBundle.object(forInfoDictionaryKey: "MeshCentralHostBundleID") as? String == BroadcastChannel.hostID,
              extensionBundle.object(forInfoDictionaryKey: "MeshCentralAppGroup") as? String == appGroup,
              extensionBundle.object(forInfoDictionaryKey: "MeshCentralKeychainGroup") as? String == BroadcastChannel.accessGroup,
              declaration?["NSExtensionPointIdentifier"] as? String == "com.apple.broadcast-services-upload",
              declaration?["RPBroadcastProcessMode"] as? String == "RPBroadcastProcessModeSampleBuffer" else {
            throw BroadcastConfigurationError.extensionConfiguration
        }
    }

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = BroadcastChannel.extensionID
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {}
}
