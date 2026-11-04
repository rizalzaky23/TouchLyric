import SwiftUI
import Combine

struct SettingsView: View {
    @EnvironmentObject var spotify: SpotifyBridgeService

    var body: some View {
        Form {
            Toggle("Show Lyrics on Touch Bar", isOn: $spotify.state.isTouchBarEnabled)
            HStack {
                Text("Cache size")
                Spacer()
                Text(CacheSizeFormatter.shared.formattedSize())
            }
        }
        .frame(width: 300, height: 150)
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
