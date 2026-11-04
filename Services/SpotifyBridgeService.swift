import Foundation
import AppKit
import Combine

final class SpotifyBridgeService: ObservableObject {
    @Published var state = TouchLyricState()
    private var smartTimer: DispatchSourceTimer?
    private var cacheService: LRCParserAndCacheService
    private var notificationObserver: Any?

    init(cacheService: LRCParserAndCacheService) {
        self.cacheService = cacheService
        subscribeToSpotifyNotifications()
        fetchCurrentTrackIfNeeded()
    }

    deinit {
        if let obs = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
        stopAllTimers()
    }

    // MARK: - DistributedNotificationCenter observer

    private func subscribeToSpotifyNotifications() {
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main) { [weak self] notif in
                self?.handlePlaybackNotification(notif)
            }
    }

    private func handlePlaybackNotification(_ notification: Notification) {
        if let info = notification.userInfo,
           let stateStr = info["Player State"] as? String {
            let pstate = PlaybackState(rawValue: stateStr.capitalized) ?? .unknown
            var track: SpotifyTrack? = nil
            if pstate != .stopped,
               let trackId = info["Track ID"] as? String {
                let title = info["Name"] as? String ?? ""
                let artist = info["Artist"] as? String ?? ""
                let durMs = (info["Duration"] as? NSNumber)?.doubleValue ?? 0
                track = SpotifyTrack(id: trackId, title: title, artist: artist, duration: durMs / 1000)
            }
            updatePlayback(state: pstate, track: track)
            return
        }
        fetchCurrentTrackIfNeeded()
    }

    // MARK: - AppleScript & Process helpers

    private var isSpotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
    }

    private func runAppleScript(_ src: String) -> String? {
        var err: NSDictionary?
        let script = NSAppleScript(source: src)
        let out = script?.executeAndReturnError(&err)
        if let e = err { NSLog("AppleScript error: \(e)") }
        return out?.stringValue
    }

    private func fetchCurrentTrackIfNeeded() {
        guard isSpotifyRunning else {
            updatePlayback(state: .stopped, track: nil)
            return
        }
        let raw = runAppleScript("tell application \"Spotify\" to player state as string") ?? "stopped"
        let pstate = PlaybackState(rawValue: raw.capitalized) ?? .unknown
        var track: SpotifyTrack? = nil
        if pstate != .stopped {
            let uri = runAppleScript("tell application \"Spotify\" to id of current track") ?? ""
            let title = runAppleScript("tell application \"Spotify\" to name of current track") ?? ""
            let artist = runAppleScript("tell application \"Spotify\" to artist of current track") ?? ""
            let durStr = runAppleScript("tell application \"Spotify\" to duration of current track") ?? "0"
            let durMs = Double(durStr) ?? 0
            track = SpotifyTrack(id: uri, title: title, artist: artist, duration: durMs/1000)
        }
        updatePlayback(state: pstate, track: track)
    }

    private func updatePlayback(state pstate: PlaybackState, track: SpotifyTrack?) {
        self.state.playbackState = pstate
        if let t = track {
            if self.state.track?.id != t.id {
                self.state.track = t
                Task { await loadLyrics(for: t) }
            }
        } else {
            self.state.track = nil
            self.state.lyrics = []
            stopAllTimers()
        }
        switch pstate {
        case .playing: scheduleSmartTimer()
        case .paused, .stopped: stopAllTimers()
        default: break
        }
    }

    // MARK: - Lyrics loading

    private func loadLyrics(for track: SpotifyTrack) async {
        do {
            let lines = try await cacheService.lyricLines(for: track)
            DispatchQueue.main.async {
                self.state.lyrics = lines
                self.state.currentLineIndex = 0
                self.scheduleSmartTimer()
            }
        } catch {
            NSLog("Lyric load failed: \(error)")
            DispatchQueue.main.async { self.state.lyrics = [] }
        }
    }

    // MARK: - Smart timer

    private func scheduleSmartTimer() {
        stopAllTimers()
        guard state.playbackState == .playing,
              let _ = state.track,
              !state.lyrics.isEmpty else { return }
        let interval = calculateNextInterval()
        guard interval > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in self?.advanceLyric() }
        timer.resume()
        smartTimer = timer
    }

    private func calculateNextInterval() -> TimeInterval {
        guard isSpotifyRunning else { return 0 }
        guard let posStr = runAppleScript("tell application \"Spotify\" to player position"),
              let cur = Double(posStr) else { return 0 }
        // find next lyric after current position
        if let nextIdx = state.lyrics.firstIndex(where: { $0.time > cur }) {
            state.currentLineIndex = max(0, nextIdx - 1)
            let nextLine = state.lyrics[nextIdx]
            return max(0, nextLine.time - cur)
        }
        return 0
    }

    private func advanceLyric() {
        guard state.currentLineIndex + 1 < state.lyrics.count else { stopAllTimers(); return }
        state.currentLineIndex += 1
        scheduleSmartTimer()
    }

    // MARK: - Public controls

    func seek(to line: LyricLine) {
        guard isSpotifyRunning else { return }
        let script = "tell application \"Spotify\" to set player position to \(line.time)"
        _ = runAppleScript(script)
        scheduleSmartTimer()
    }

    func offsetCurrentPosition(by delta: TimeInterval) {
        guard isSpotifyRunning else { return }
        guard let posStr = runAppleScript("tell application \"Spotify\" to player position"),
              let cur = Double(posStr) else { return }
        let newPos = max(0, cur + delta)
        _ = runAppleScript("tell application \"Spotify\" to set player position to \(newPos)")
        scheduleSmartTimer()
    }

    func stopAllTimers() {
        smartTimer?.cancel()
        smartTimer = nil
    }
}
