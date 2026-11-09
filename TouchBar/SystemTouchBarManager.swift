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
        (state.playbackState == .playing || state.playbackState == .paused) &&
        !state.lyrics.isEmpty &&
        state.currentLineIndex >= 0 &&
        state.lyrics.indices.contains(state.currentLineIndex)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .foregroundColor(state.playbackState != .stopped ? Color(red: 0.11, green: 0.84, blue: 0.38) : .secondary)

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

// MARK: - Word-by-Word Lyric Timing Model
private struct WordTiming {
    let word: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

// MARK: - Lyric Color Follow View (Teks menyala hijau per kata mengikuti vokal)
private struct LyricColorFollowView: View {
    @ObservedObject var state: TouchLyricState
    let line: LyricLine
    let text: String
    let lineIndex: Int

    private var wordTimings: [WordTiming] {
        let startTime = line.time
        let endTime = state.nextLineTime
        let rawDuration = max(0.5, endTime - startTime)

        // Estimasi durasi vokal jika ada jeda melodi/solo panjang
        let singingDuration: Double = {
            if rawDuration <= 7.0 {
                return rawDuration
            }
            let charBased = Double(max(10, text.count)) * 0.18
            return min(rawDuration, max(3.0, min(charBased, 6.5)))
        }()

        let rawWords = text.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !rawWords.isEmpty else { return [] }

        // Bobot tiap kata dihitung berdasarkan suku kata (vokal) dan panjang kata
        // agar kata pendek ("dan", "kau") dan kata panjang ("mempertahankan") pas dengan ucapan penyanyi
        let weights = rawWords.map { word -> Double in
            let lower = word.lowercased()
            let vowels = lower.filter { "aiueoy".contains($0) }.count
            let charBonus = Double(max(1, word.count)) * 0.1
            return max(1.0, Double(vowels) + charBonus)
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return [] }

        var result: [WordTiming] = []
        var currentAccWeight: Double = 0

        for (index, word) in rawWords.enumerated() {
            let w = weights[index]
            let wordStart = startTime + singingDuration * (currentAccWeight / totalWeight)
            currentAccWeight += w
            let wordEnd = startTime + singingDuration * (currentAccWeight / totalWeight)
            result.append(WordTiming(word: word, startTime: wordStart, endTime: wordEnd))
        }

        return result
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: state.playbackState != .playing)) { context in
            let now = context.date
            let elapsed = state.playbackState == .playing ? now.timeIntervalSince(state.lastPositionTimestamp) : 0
            let currentPos = state.lastKnownPosition + elapsed

            let timings = wordTimings

            Text(buildAttributedLyric(timings: timings, currentPos: currentPos))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .id(lineIndex)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 3)),
                        removal: .opacity.combined(with: .offset(y: -3))
                    )
                )
        }
    }

    private func buildAttributedLyric(timings: [WordTiming], currentPos: TimeInterval) -> AttributedString {
        guard !timings.isEmpty else {
            var plain = AttributedString(text)
            plain.foregroundColor = Color.white
            return plain
        }

        var result = AttributedString()
        let greenColor = Color(red: 0.11, green: 0.84, blue: 0.38) // Spotify Green
        let whiteColor = Color.white

        for (index, item) in timings.enumerated() {
            var wordAttr = AttributedString(item.word)
            let isSung = currentPos >= item.startTime
            wordAttr.foregroundColor = isSung ? greenColor : whiteColor

            result.append(wordAttr)

            if index < timings.count - 1 {
                var spaceAttr = AttributedString(" ")
                let nextIsSung = currentPos >= timings[index + 1].startTime
                spaceAttr.foregroundColor = nextIsSung ? greenColor : whiteColor
                result.append(spaceAttr)
            }
        }

        return result
    }
}
