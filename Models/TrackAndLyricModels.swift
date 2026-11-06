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
