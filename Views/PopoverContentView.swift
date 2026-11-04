import SwiftUI
import AppKit

struct PopoverContentView: View {
    @EnvironmentObject var spotify: SpotifyBridgeService
    @EnvironmentObject var touchBarMgr: SystemTouchBarManager

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            lyricsScrollView
            Divider()
            controlsBar
        }
        .frame(width: 320, height: 420)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .onAppear {
            if spotify.state.isTouchBarEnabled && !touchBarMgr.isPresented {
                touchBarMgr.presentSystemTouchBar()
            }
        }
        .onChange(of: spotify.state.isTouchBarEnabled) { enabled in
            if enabled {
                touchBarMgr.presentSystemTouchBar()
            } else {
                touchBarMgr.dismissSystemTouchBar()
            }
        }
    }

    // MARK: Header
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(spotify.state.track?.title ?? "—")
                .font(.headline)
                .lineLimit(1)
            Text(spotify.state.track?.artist ?? "—")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(spotify.state.playbackState.rawValue)
                .font(.caption)
                .foregroundColor(spotify.state.playbackState == .playing ? .green : .orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Lyrics Scroll
    private var lyricsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(spotify.state.lyrics) { line in
                        Text(line.text)
                            .font(line.id == spotify.state.lyrics[spotify.state.currentLineIndex].id ? .system(size: 14, weight: .semibold) : .system(size: 13))
                            .foregroundColor(line.id == spotify.state.lyrics[spotify.state.currentLineIndex].id ? .accentColor : .primary)
                            .onTapGesture { spotify.seek(to: line) }
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: spotify.state.currentLineIndex) { newIdx in
                withAnimation(.easeInOut(duration: 0.2)) {
                    let targetID = spotify.state.lyrics[newIdx].id
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
    }

    // MARK: Controls
    private var controlsBar: some View {
        HStack(spacing: 12) {
            Button(action: { spotify.offsetCurrentPosition(by: -0.5) }) {
                Image(systemName: "gobackward.minus")
            }
            Button(action: { spotify.offsetCurrentPosition(by: 0.5) }) {
                Image(systemName: "goforward.plus")
            }
            Spacer()
            Toggle(isOn: $spotify.state.isTouchBarEnabled) {
                Image(systemName: "rectangle.and.pencil.and.outline")
            }
            .toggleStyle(.button)
            Button(action: { /* open settings */ }) {
                Image(systemName: "gearshape")
            }
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "xmark.circle")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: VisualEffectView wrapper
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
