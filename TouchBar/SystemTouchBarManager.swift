import Cocoa
import SwiftUI
import Combine
import Darwin

final class SystemTouchBarManager: NSObject, ObservableObject {
    var objectWillChange = ObservableObjectPublisher()
    private var touchBar: NSTouchBar?
    @Published var isPresented = false
    private weak var spotifyService: SpotifyBridgeService?
    private var cancellables = Set<AnyCancellable>()


    func inject(spotifyService: SpotifyBridgeService) {
        self.spotifyService = spotifyService
        buildTouchBar()
    }

    private func dfrSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        let handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)
        guard handle != nil else { return nil }
        return dlsym(handle, name)
    }
    func addControlStripButton() {
        guard let fnPtr = dfrSymbol("DFRElementSetControlStripPresenceForIdentifier") else { return }
        let fn = unsafeBitCast(fnPtr, to: (@convention(c) (NSString, Bool) -> Void).self)
        fn("com.rizal.TouchLyric.toggle" as NSString, true)
    }

    @objc func toggleSystemTouchBar() {
        isPresented ? dismissSystemTouchBar() : presentSystemTouchBar()
    }

    func presentSystemTouchBar() {
        guard let tb = touchBar,
              let fnPtr = dfrSymbol("NSTouchBarPresentSystemModalTouchBar") else { return }
        let fn = unsafeBitCast(fnPtr, to: (@convention(c) (NSTouchBar) -> Void).self)
        fn(tb)
        isPresented = true
    }

    func dismissSystemTouchBar() {
        guard let fnPtr = dfrSymbol("NSTouchBarDismissSystemModalTouchBar") else { return }
        let fn = unsafeBitCast(fnPtr, to: (@convention(c) () -> Void).self)
        fn()
        isPresented = false
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
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        svc.state.$currentLineIndex.receive(on: DispatchQueue.main).sink { idx in
            let txt = svc.state.lyrics[safe: idx]?.text ?? ""
            label.stringValue = txt
        }.store(in: &cancellables)
        item.view = label
        return item
    }
}

// Helper safely index arrays
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
