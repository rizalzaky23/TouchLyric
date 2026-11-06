import Cocoa
import SwiftUI
import Combine

final class SystemTouchBarManager: NSObject, ObservableObject {
    var objectWillChange = ObservableObjectPublisher()
    private var touchBar: NSTouchBar?
    @Published var isPresented = false
    private weak var spotifyService: SpotifyBridgeService?
    private var cancellables = Set<AnyCancellable>()
    private let controlStripID = NSTouchBarItem.Identifier("com.rizal.TouchLyric.controlStrip")
    private var controlStripItem: NSCustomTouchBarItem?

    func inject(spotifyService: SpotifyBridgeService) {
        self.spotifyService = spotifyService
        buildTouchBar()

        // Auto-present touchbar when playing
        spotifyService.state.$playbackState
            .combineLatest(spotifyService.state.$isTouchBarEnabled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pstate, enabled in
                guard let self = self else { return }
                if enabled && pstate == .playing && !self.isPresented {
                    self.presentSystemTouchBar()
                }
            }
            .store(in: &cancellables)
    }

    func addControlStripButton() {
        let item = NSCustomTouchBarItem(identifier: controlStripID)
        let btn = NSButton(image: NSImage(systemSymbolName: "music.note", accessibilityDescription: "TouchLyric") ?? NSImage(), target: self, action: #selector(toggleSystemTouchBar))
        item.view = btn
        self.controlStripItem = item

        let addTraySel = NSSelectorFromString("addSystemTrayItem:")
        if NSTouchBarItem.responds(to: addTraySel) {
            NSTouchBarItem.perform(addTraySel, with: item)
        }

        DFR_SetControlStripPresence(controlStripID.rawValue, true)
        DFR_SetShowsCloseBox(true)
    }

    @objc func toggleSystemTouchBar() {
        isPresented ? dismissSystemTouchBar() : presentSystemTouchBar()
    }

    func presentSystemTouchBar() {
        guard let tb = touchBar else { return }
        let presentSel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        if NSTouchBar.responds(to: presentSel) {
            NSTouchBar.perform(presentSel, with: tb, with: controlStripID.rawValue)
            isPresented = true
            print("[TouchLyric] System modal Touch Bar presented")
        }
    }

    func dismissSystemTouchBar() {
        guard let tb = touchBar else { return }
        let dismissSel = NSSelectorFromString("dismissSystemModalTouchBar:")
        if NSTouchBar.responds(to: dismissSel) {
            NSTouchBar.perform(dismissSel, with: tb)
            isPresented = false
            print("[TouchLyric] System modal Touch Bar dismissed")
        }
    }

    // MARK: - Build Touch Bar UI
    private func buildTouchBar() {
        let tb = NSTouchBar()
        tb.delegate = self
        tb.defaultItemIdentifiers = [.init("TouchLyric.activeLine")]
        self.touchBar = tb
    }
}

extension SystemTouchBarManager: NSTouchBarDelegate {
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier.rawValue == "TouchLyric.activeLine",
              let svc = spotifyService else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = NSHostingView(rootView: TouchBarLyricView(state: svc.state))
        return item
    }
}

// MARK: - Touch Bar SwiftUI View
struct TouchBarLyricView: View {
    @ObservedObject var state: TouchLyricState

    var body: some View {
        HStack(spacing: 10) {
            AnimatedEqualizerView(isPlaying: state.playbackState == .playing)

            if let track = state.track {
                if !state.lyrics.isEmpty && state.currentLineIndex >= 0 && state.lyrics.indices.contains(state.currentLineIndex) {
                    let line = state.lyrics[state.currentLineIndex]
                    KaraokeLineView(
                        state: state,
                        line: line,
                        lineIndex: state.currentLineIndex,
                        track: track
                    )
                } else if state.playbackState == .playing {
                    NowPlayingFallbackView(
                        title: track.title,
                        artist: track.artist,
                        isPlaying: true
                    )
                } else {
                    NowPlayingFallbackView(
                        title: track.title,
                        artist: track.artist,
                        isPlaying: false
                    )
                }
            } else {
                Text("TouchLyric: Buka Spotify untuk memutar lagu")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Karaoke Lyric Line View (Real-time animated progress & sweep)
private struct KaraokeLineView: View {
    @ObservedObject var state: TouchLyricState
    let line: LyricLine
    let lineIndex: Int
    let track: SpotifyTrack
    @State private var textWidth: CGFloat = 0

    private var displayText: String {
        line.text.isEmpty ? "🎵 \(track.title)" : line.text
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: state.playbackState != .playing)) { context in
            let now = context.date
            let elapsed = state.playbackState == .playing ? now.timeIntervalSince(state.lastPositionTimestamp) : 0
            let currentPos = state.lastKnownPosition + elapsed

            let startTime = line.time
            let endTime = state.nextLineTime
            let rawDuration = max(0.5, endTime - startTime)

            // Estimate vocal singing duration so instrumental solos don't drag the sweep
            let singingDuration: Double = {
                if rawDuration <= 7.0 {
                    return rawDuration
                }
                let charBased = Double(max(10, displayText.count)) * 0.18
                return min(rawDuration, max(3.0, min(charBased, 6.5)))
            }()

            let rawProgress = (currentPos - startTime) / singingDuration
            let progress = min(max(rawProgress, 0.0), 1.0)

            GeometryReader { containerGeo in
                let containerWidth = max(50, containerGeo.size.width)
                let excess = max(0, textWidth - containerWidth)
                let scrollOffset = excess > 0 ? -excess * CGFloat(progress) : 0

                VStack(alignment: .leading, spacing: 3) {
                    ZStack(alignment: .leading) {
                        // Base unhighlighted lyric
                        Text(displayText)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.35))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .background(
                                GeometryReader { textGeo in
                                    Color.clear.preference(
                                        key: LyricTextWidthKey.self,
                                        value: textGeo.size.width
                                    )
                                }
                            )

                        // Active glowing karaoke sweep
                        Text(displayText)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.15, green: 0.90, blue: 0.45),
                                        Color.white
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: Color(red: 0.11, green: 0.84, blue: 0.38).opacity(0.55), radius: 4, x: 0, y: 0)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .mask(
                                GeometryReader { maskGeo in
                                    let w = maskGeo.size.width
                                    let fillWidth = max(0, min(w, w * CGFloat(progress)))
                                    HStack(spacing: 0) {
                                        Rectangle()
                                            .frame(width: max(0, fillWidth - 6))
                                        LinearGradient(
                                            colors: [Color.black, Color.clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        .frame(width: min(8, fillWidth))
                                        Spacer(minLength: 0)
                                    }
                                }
                            )
                    }
                    .offset(x: scrollOffset)
                    .id(lineIndex)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 4)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        )
                    )

                    // Line progress bar indicator
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 2)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.11, green: 0.84, blue: 0.38),
                                        Color(red: 0.35, green: 0.95, blue: 0.55)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, containerWidth * CGFloat(progress)), height: 2)
                            .shadow(color: Color(red: 0.11, green: 0.84, blue: 0.38).opacity(0.8), radius: 2)
                    }
                    .frame(height: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .clipped()
            }
            .onPreferenceChange(LyricTextWidthKey.self) { newWidth in
                self.textWidth = newWidth
            }
        }
    }
}

// MARK: - Animated Equalizer Bars View
private struct AnimatedEqualizerView: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                EqualizerBar(time: t, phase: 0.0, isPlaying: isPlaying)
                EqualizerBar(time: t, phase: 1.8, isPlaying: isPlaying)
                EqualizerBar(time: t, phase: 3.6, isPlaying: isPlaying)
                EqualizerBar(time: t, phase: 5.2, isPlaying: isPlaying)
            }
            .frame(width: 14, height: 16)
        }
    }
}

private struct EqualizerBar: View {
    let time: Double
    let phase: Double
    let isPlaying: Bool

    private var height: CGFloat {
        guard isPlaying else { return 3 }
        let wave = (sin(time * 6.0 + phase) + cos(time * 3.8 + phase * 0.7) + 2.0) / 4.0
        return CGFloat(3.0 + wave * 11.0)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.84, blue: 0.38),
                        Color(red: 0.35, green: 0.95, blue: 0.55)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 2, height: height)
    }
}

// MARK: - Fallback View (Song title / Instrumental / Paused)
private struct NowPlayingFallbackView: View {
    let title: String
    let artist: String
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(isPlaying ? "🎵" : "⏸")
                .font(.system(size: 12))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Text("•")
                .foregroundColor(Color.white.opacity(0.4))
            Text(artist)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(Color.white.opacity(0.75))
        }
        .lineLimit(1)
    }
}

// MARK: - PreferenceKey for Measuring Text Width
private struct LyricTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}
