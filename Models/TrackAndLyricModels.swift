import Foundation
import Combine
import SwiftUI
import AppKit

struct SpotifyTrack: Identifiable, Equatable {
    let id: String               // Spotify URI
    let title: String
    let artist: String
    let duration: TimeInterval   // seconds
}

struct LyricLine: Identifiable, Comparable {
    let id = UUID()
    let time: TimeInterval       // seconds from start
    let text: String

    static func < (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.time < rhs.time
    }
}

enum PlaybackState: String {
    case playing = "Playing"
    case paused  = "Paused"
    case stopped = "Stopped"
    case unknown = "Unknown"
}

enum LyricFontChoice: String, CaseIterable, Identifiable {
    case system = "System"
    case rounded = "Rounded"
    case serif = "Serif"
    case monospaced = "Monospaced"

    var id: String { rawValue }

    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

enum LyricFontWeight: String, CaseIterable, Identifiable {
    case regular = "Regular"
    case medium = "Medium"
    case semibold = "Semibold"
    case bold = "Bold"

    var id: String { rawValue }

    var weight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

final class TouchLyricAppearance: ObservableObject {
    static let defaultBaseHex = "#FFFFFF"
    static let defaultActiveHex = "#1CD661"
    static let defaultFontSize: Double = 14
    static let minFontSize: Double = 10
    static let maxFontSize: Double = 20

    private let defaults: UserDefaults

    @Published var baseColorHex: String {
        didSet { defaults.set(baseColorHex, forKey: Keys.baseColor) }
    }
    @Published var activeColorHex: String {
        didSet { defaults.set(activeColorHex, forKey: Keys.activeColor) }
    }
    @Published var fontChoice: LyricFontChoice {
        didSet { defaults.set(fontChoice.rawValue, forKey: Keys.fontChoice) }
    }
    @Published var fontWeight: LyricFontWeight {
        didSet { defaults.set(fontWeight.rawValue, forKey: Keys.fontWeight) }
    }
    @Published var fontSize: Double {
        didSet {
            let clamped = Self.clampFontSize(fontSize)
            if clamped != fontSize {
                fontSize = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.fontSize)
        }
    }
    @Published var showMusicIcon: Bool {
        didSet { defaults.set(showMusicIcon, forKey: Keys.showMusicIcon) }
    }

    private enum Keys {
        static let baseColor = "appearance.baseColorHex"
        static let activeColor = "appearance.activeColorHex"
        static let fontChoice = "appearance.fontChoice"
        static let fontWeight = "appearance.fontWeight"
        static let fontSize = "appearance.fontSize"
        static let showMusicIcon = "appearance.showMusicIcon"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.baseColorHex = defaults.string(forKey: Keys.baseColor) ?? Self.defaultBaseHex
        self.activeColorHex = defaults.string(forKey: Keys.activeColor) ?? Self.defaultActiveHex
        self.fontChoice = LyricFontChoice(rawValue: defaults.string(forKey: Keys.fontChoice) ?? "") ?? .system
        self.fontWeight = LyricFontWeight(rawValue: defaults.string(forKey: Keys.fontWeight) ?? "") ?? .semibold
        let storedSize = defaults.object(forKey: Keys.fontSize) as? Double ?? Self.defaultFontSize
        self.fontSize = Self.clampFontSize(storedSize)
        self.showMusicIcon = defaults.object(forKey: Keys.showMusicIcon) as? Bool ?? true
    }

    var baseColor: Color {
        get { Color(hex: baseColorHex) ?? .white }
        set { baseColorHex = newValue.toHex() ?? Self.defaultBaseHex }
    }

    var activeColor: Color {
        get { Color(hex: activeColorHex) ?? Color(red: 0.11, green: 0.84, blue: 0.38) }
        set { activeColorHex = newValue.toHex() ?? Self.defaultActiveHex }
    }

    var lyricFont: Font {
        .system(size: fontSize, weight: fontWeight.weight, design: fontChoice.design)
    }

    func resetToDefaults() {
        baseColorHex = Self.defaultBaseHex
        activeColorHex = Self.defaultActiveHex
        fontChoice = .system
        fontWeight = .semibold
        fontSize = Self.defaultFontSize
        showMusicIcon = true
    }

    static func clampFontSize(_ value: Double) -> Double {
        min(max(value, minFontSize), maxFontSize)
    }
}

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

final class TouchLyricState: ObservableObject {
    @Published var track: SpotifyTrack?
    @Published var lyrics: [LyricLine] = []
    @Published var currentLineIndex: Int = 0
    @Published var playbackState: PlaybackState = .unknown
    @Published var isTouchBarEnabled: Bool = true
    @Published var lastKnownPosition: TimeInterval = 0
    @Published var lastPositionTimestamp: Date = Date()

    var currentLine: LyricLine? {
        guard !lyrics.isEmpty, lyrics.indices.contains(currentLineIndex) else { return nil }
        return lyrics[currentLineIndex]
    }

    var nextLineTime: TimeInterval {
        guard !lyrics.isEmpty, lyrics.indices.contains(currentLineIndex) else { return 0 }
        let nextIndex = currentLineIndex + 1
        if lyrics.indices.contains(nextIndex) {
            return lyrics[nextIndex].time
        }
        if let track = track, track.duration > lyrics[currentLineIndex].time {
            return min(track.duration, lyrics[currentLineIndex].time + 6.0)
        }
        return lyrics[currentLineIndex].time + 4.0
    }
}
