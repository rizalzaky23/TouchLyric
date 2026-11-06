import Foundation
import AppKit
import Combine
import SwiftUI

final class SpotifyBridgeService: NSObject, ObservableObject {
    @Published var state = TouchLyricState()
    private var syncTimer: DispatchSourceTimer?
    private var cacheService: LRCParserAndCacheService
    private var cancellables = Set<AnyCancellable>()
    private var lastKnownPosition: TimeInterval = 0
    private var lastPositionTimestamp: Date = Date()
    private var pollCounter: Int = 0

    init(cacheService: LRCParserAndCacheService) {
        self.cacheService = cacheService
        super.init()

        // Forward nested state changes so any SwiftUI view observing SpotifyBridgeService updates
        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        subscribeToSpotifyNotifications()
        fetchCurrentTrackIfNeeded()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        stopSyncTimer()
    }

    // MARK: - DistributedNotificationCenter observer

    private func subscribeToSpotifyNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSpotifyNotification(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func handleSpotifyNotification(_ notification: Notification) {
        if let info = notification.userInfo {
            let stateStr = info["Player State"] as? String ?? ""
            let pstate = PlaybackState(rawValue: stateStr.capitalized) ?? .unknown

            var track: SpotifyTrack? = nil
            if pstate != .stopped, let trackId = info["Track ID"] as? String {
                let title = info["Name"] as? String ?? ""
                let artist = info["Artist"] as? String ?? ""
                let durMs = (info["Duration"] as? NSNumber)?.doubleValue ?? 0
                track = SpotifyTrack(id: trackId, title: title, artist: artist, duration: durMs / 1000)
            }

            let pos = (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0
            self.recordPosition(pos)

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

    func fetchCurrentTrackIfNeeded() {
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
            track = SpotifyTrack(id: uri, title: title, artist: artist, duration: durMs / 1000)

            if let posStr = runAppleScript("tell application \"Spotify\" to player position"),
               let pos = Double(posStr.replacingOccurrences(of: ",", with: ".")) {
                self.recordPosition(pos)
            }
        }
        updatePlayback(state: pstate, track: track)
    }

    private func recordPosition(_ pos: TimeInterval) {
        self.lastKnownPosition = pos
        let now = Date()
        self.lastPositionTimestamp = now
        self.state.lastKnownPosition = pos
        self.state.lastPositionTimestamp = now
    }

    private func updatePlayback(state pstate: PlaybackState, track: SpotifyTrack?) {
        self.state.playbackState = pstate
        if let t = track {
            if self.state.track?.id != t.id {
                print("[TouchLyric] New track detected: \(t.title) by \(t.artist)")
                self.state.track = t
                self.state.lyrics = []
                self.state.currentLineIndex = -1
                Task { await loadLyrics(for: t) }
            }
        } else {
            self.state.track = nil
            self.state.lyrics = []
            self.state.currentLineIndex = 0
        }

        switch pstate {
        case .playing:
            startSyncTimer()
        case .paused, .stopped:
            stopSyncTimer()
        default:
            break
        }
    }

    // MARK: - Lyrics loading

    private func loadLyrics(for track: SpotifyTrack) async {
        do {
            let lines = try await cacheService.lyricLines(for: track)
            await MainActor.run {
                guard self.state.track?.id == track.id else { return }
                self.state.lyrics = lines
                self.tickSync()
            }
        } catch {
            NSLog("Lyric load failed: \(error)")
            await MainActor.run {
                guard self.state.track?.id == track.id else { return }
                self.state.lyrics = []
            }
        }
    }

    // MARK: - Playback synchronization timer

    private func startSyncTimer() {
        stopSyncTimer()
        guard state.playbackState == .playing else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.tickSync()
        }
        timer.resume()
        syncTimer = timer
    }

    private func stopSyncTimer() {
        syncTimer?.cancel()
        syncTimer = nil
    }

    private func tickSync() {
        guard state.playbackState == .playing, isSpotifyRunning else { return }

        // Every ~2 seconds (20 ticks @ 100ms), resync exact position & check track with Spotify
        pollCounter += 1
        if pollCounter >= 20 {
            pollCounter = 0
            resyncWithSpotify()
        }

        // Calculate estimated current position based on elapsed time
        let elapsed = Date().timeIntervalSince(lastPositionTimestamp)
        let currentPos = lastKnownPosition + elapsed

        guard !state.lyrics.isEmpty else { return }

        // Find active lyric line for current position
        if let idx = state.lyrics.lastIndex(where: { $0.time <= currentPos }) {
            if state.currentLineIndex != idx {
                withAnimation(.easeInOut(duration: 0.25)) {
                    state.currentLineIndex = idx
                }
            }
        } else {
            let firstTime = state.lyrics.first?.time ?? 0
            if firstTime - currentPos <= 3.5 {
                if state.currentLineIndex != 0 {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        state.currentLineIndex = 0
                    }
                }
            } else {
                if state.currentLineIndex != -1 {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        state.currentLineIndex = -1
                    }
                }
            }
        }
    }

    private func resyncWithSpotify() {
        guard isSpotifyRunning else { return }
        if let posStr = runAppleScript("tell application \"Spotify\" to player position"),
           let cur = Double(posStr.replacingOccurrences(of: ",", with: ".")) {
            recordPosition(cur)
        }

        // Check if track changed (safety net if notification was delayed)
        if let currentTrackId = runAppleScript("tell application \"Spotify\" to id of current track"),
           !currentTrackId.isEmpty {
            if state.track == nil || state.track?.id != currentTrackId {
                fetchCurrentTrackIfNeeded()
            }
        }
    }

    // MARK: - Public controls

    func seek(to line: LyricLine) {
        guard isSpotifyRunning else { return }
        let script = "tell application \"Spotify\" to set player position to \(line.time)"
        _ = runAppleScript(script)
        recordPosition(line.time)
        if let idx = state.lyrics.firstIndex(where: { $0.id == line.id }) {
            withAnimation(.easeInOut(duration: 0.25)) {
                state.currentLineIndex = idx
            }
        }
    }

    func offsetCurrentPosition(by delta: TimeInterval) {
        guard isSpotifyRunning else { return }
        guard let posStr = runAppleScript("tell application \"Spotify\" to player position"),
              let cur = Double(posStr.replacingOccurrences(of: ",", with: ".")) else { return }
        let newPos = max(0, cur + delta)
        _ = runAppleScript("tell application \"Spotify\" to set player position to \(newPos)")
        recordPosition(newPos)
        tickSync()
    }

    func stopAllTimers() {
        stopSyncTimer()
    }
}
