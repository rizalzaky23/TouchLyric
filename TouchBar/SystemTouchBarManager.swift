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

    private var currentText: String {
        if let track = state.track {
            if !state.lyrics.isEmpty && state.lyrics.indices.contains(state.currentLineIndex) {
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .foregroundColor(.green)
            Text(currentText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
