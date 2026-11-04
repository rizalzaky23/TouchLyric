import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var touchBarManager: SystemTouchBarManager!
    private var spotifyService: SpotifyBridgeService!
    private var cacheService: LRCParserAndCacheService!

    func applicationDidFinishLaunching(_ notification: Notification) {
        cacheService = LRCParserAndCacheService()
        spotifyService = SpotifyBridgeService(cacheService: cacheService)
        touchBarManager = SystemTouchBarManager()
        touchBarManager.inject(spotifyService: spotifyService)

        NSApp.setActivationPolicy(.regular)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "TouchLyric")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }


        // Popover
        let vc = NSHostingController(rootView: PopoverContentView()
                                            .environmentObject(spotifyService)
                                            .environmentObject(touchBarManager))
        popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 420)

        // Control‑strip button via private API
        touchBarManager.addControlStripButton()

        // Auto-present Touch Bar on launch
        if spotifyService.state.isTouchBarEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.touchBarManager.presentSystemTouchBar()
            }
        }
    }

        @objc private func togglePopover(_ sender: Any?) {
            if popover.isShown {
                popover.performClose(sender)
            } else if let button = statusItem.button {
                // Bring app to front (needed for LSUIElement)
                NSApp.activate(ignoringOtherApps: true)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
                print("[TouchLyric] Popover shown")
            }
        }

    func applicationWillTerminate(_ notification: Notification) {
        spotifyService.stopAllTimers()
        touchBarManager.dismissSystemTouchBar()
    }
}
