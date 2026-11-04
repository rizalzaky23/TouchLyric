import Foundation
import Combine

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

final class TouchLyricState: ObservableObject {
    @Published var track: SpotifyTrack?
    @Published var lyrics: [LyricLine] = []
    @Published var currentLineIndex: Int = 0
    @Published var playbackState: PlaybackState = .unknown
    @Published var isTouchBarEnabled: Bool = true
}
