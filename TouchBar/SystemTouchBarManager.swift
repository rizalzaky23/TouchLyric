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

        // Auto-present touchbar when Spotify is playing, auto-dismiss when stopped
        spotifyService.state.$playbackState
            .combineLatest(spotifyService.state.$isTouchBarEnabled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pstate, enabled in
                guard let self = self else { return }
                if enabled && pstate == .playing {
                    if !self.isPresented {
                        self.presentSystemTouchBar()
                    }
                } else if pstate == .stopped || !enabled {
                    if self.isPresented {
                        self.dismissSystemTouchBar()
                    }
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

    private var currentText: String {
        if let track = state.track {
            if !state.lyrics.isEmpty && state.currentLineIndex >= 0 && state.lyrics.indices.contains(state.currentLineIndex) {
                let line = state.lyrics[state.currentLineIndex].text
                return line.isEmpty ? "🎵 \(track.title)" : line
            } else if state.playbackState == .playing {
                return "🎵 \(track.title) - \(track.artist)"
            } else {
                return "⏸ \(track.title) - \(track.artist)"
            }
        }
        return "TouchLyric: Buka Spotify untuk memutar lagu"
    }

    private var isSyncedLyricActive: Bool {
        state.playbackState == .playing &&
        !state.lyrics.isEmpty &&
        state.currentLineIndex >= 0 &&
        state.lyrics.indices.contains(state.currentLineIndex)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .foregroundColor(state.playbackState == .playing ? Color(red: 0.11, green: 0.84, blue: 0.38) : .secondary)

            if isSyncedLyricActive {
                let line = state.lyrics[state.currentLineIndex]
                LyricColorFollowView(
                    state: state,
                    line: line,
                    text: currentText,
                    lineIndex: state.currentLineIndex
                )
            } else {
                Text(currentText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Lyric Color Follow View (Teks putih berubah hijau saat dinyanyikan)
private struct LyricColorFollowView: View {
    @ObservedObject var state: TouchLyricState
    let line: LyricLine
    let text: String
    let lineIndex: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: state.playbackState != .playing)) { context in
            let now = context.date
            let elapsed = state.playbackState == .playing ? now.timeIntervalSince(state.lastPositionTimestamp) : 0
            let currentPos = state.lastKnownPosition + elapsed

            let startTime = line.time
            let endTime = state.nextLineTime
            let rawDuration = max(0.5, endTime - startTime)

            // Estimasi durasi vokal agar saat jeda melodi/solo tidak terseret lambat
            let singingDuration: Double = {
                if rawDuration <= 7.0 {
                    return rawDuration
                }
                let charBased = Double(max(10, text.count)) * 0.18
                return min(rawDuration, max(3.0, min(charBased, 6.5)))
            }()

            let rawProgress = (currentPos - startTime) / singingDuration
            let progress = min(max(rawProgress, 0.0), 1.0)

            ZStack(alignment: .leading) {
                // Teks dasar putih (persis seperti tampilan sebelumnya)
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Warna hijau aktif saat lirik dinyanyikan (mengikuti kata demi kata)
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.11, green: 0.84, blue: 0.38)) // Spotify Green
                    .lineLimit(1)
                    .mask(
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                Rectangle()
                                    .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(progress))))
                                Spacer(minLength: 0)
                            }
                        }
                    )
            }
            .id(lineIndex)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 3)),
                    removal: .opacity.combined(with: .offset(y: -3))
                )
            )
        }
    }
}
