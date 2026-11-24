import SwiftUI
import Combine
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var spotify: SpotifyBridgeService
    @EnvironmentObject var appearance: TouchLyricAppearance
    @State private var launchAtLogin: Bool = {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }()

    var body: some View {
        Form {
            Section("Touch Bar Preview") {
                touchBarPreview
            }

            Section("Appearance") {
                ColorPicker("Base Text Color", selection: $appearance.baseColor, supportsOpacity: false)
                ColorPicker("Active Lyric Color", selection: $appearance.activeColor, supportsOpacity: false)

                Picker("Font Style", selection: $appearance.fontChoice) {
                    ForEach(LyricFontChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }

                Picker("Font Weight", selection: $appearance.fontWeight) {
                    ForEach(LyricFontWeight.allCases) { weight in
                        Text(weight.rawValue).tag(weight)
                    }
                }

                HStack {
                    Text("Font Size")
                    Slider(
                        value: $appearance.fontSize,
                        in: TouchLyricAppearance.minFontSize...TouchLyricAppearance.maxFontSize,
                        step: 1
                    )
                    Text("\(Int(appearance.fontSize)) pt")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }

                Toggle("Show Music Icon", isOn: $appearance.showMusicIcon)

                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        appearance.resetToDefaults()
                    }
                }
            }

            Section("General") {
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
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 470)
    }

    private var touchBarPreview: some View {
        HStack(spacing: 8) {
            if appearance.showMusicIcon {
                Image(systemName: "music.note")
                    .foregroundColor(appearance.activeColor)
            }
            Text(previewAttributedLyric)
                .font(appearance.lyricFont)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .center)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var previewAttributedLyric: AttributedString {
        var sung = AttributedString("Never gonna give ")
        sung.foregroundColor = appearance.activeColor
        var unsung = AttributedString("you up")
        unsung.foregroundColor = appearance.baseColor
        sung.append(unsung)
        return sung
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
