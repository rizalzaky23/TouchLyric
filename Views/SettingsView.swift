import SwiftUI
import Combine
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var spotify: SpotifyBridgeService
    @State private var launchAtLogin: Bool = {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }()

    var body: some View {
        Form {
            Toggle("Show Lyrics on Touch Bar", isOn: $spotify.state.isTouchBarEnabled)

            if #available(macOS 13.0, *) {
                Toggle("Launch at Login (Background)", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                ))
            }

            HStack {
                Text("Cache size")
                Spacer()
                Text(CacheSizeFormatter.shared.formattedSize())
            }
        }
        .frame(width: 320, height: 160)
        .padding()
    }
}

final class CacheSizeFormatter {
    static let shared = CacheSizeFormatter()
    private init() {}
    func formattedSize() -> String {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folder = caches.appendingPathComponent("TouchLyricLRC")
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return "0 B" }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += UInt64(size)
            }
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(total))
    }
}
