# TouchLyric – Lyrics on the macOS Touch Bar

TouchLyric is a native macOS application that synchronises Spotify playback with LRC‑formatted lyrics and shows the current line on the system‑wide Touch Bar. It lives as a menu‑bar (UI‑element) app, never appears in the Dock, and works completely event‑driven – no polling, zero CPU when Spotify is paused.

## ✨ Features

| Feature                     | Description |
|-----------------------------|-------------|
| **System‑wide Touch Bar**   | Shows the active lyric line even when another app is frontmost, using private `DFRFoundation` APIs. |
| **Menu‑bar pop‑over UI**    | Click the music‑note icon in the menu bar to open a SwiftUI pop‑over with song title, artist, playback status, full lyrics list, and controls. |
| **Smart timer**             | After each lyric line is displayed, a `DispatchSourceTimer` is scheduled exactly for the next timestamp (`[mm:ss.xx]`). No polling, 0 % CPU when paused/stopped. |
| **Spotify integration**     | Listens to `com.spotify.client.PlaybackStateChanged` via `DistributedNotificationCenter`. Uses AppleScript (`NSAppleScript`) to read/write player position only on start/seek. |
| **LRCLIB caching**          | Downloads lyrics from `https://lrclib.net/api/get?...` and stores them in `~/Library/Caches/TouchLyricLRC`. Subsequent plays of the same track are served from cache. |
| **Offset controls**         | Buttons to shift the sync by ±0.5 s, and a toggle to enable/disable the Touch Bar display. |
| **Settings pane** (stub)    | Placeholder for future preferences (cache size, offset defaults, theme). |
| **No sandbox**              | Required for AppleScript automation and private API usage (`com.apple.security.app-sandbox = false`). |

## 📦 Installation

1. **Clone the repo**
   ```bash
   git clone https://github.com/rizalzaky23/TouchLyric.git
   cd TouchLyric
   ```
2. **Open in Xcode** (tested with Xcode 15, macOS 13+).
   ```bash
   open TouchLyric.xcodeproj
   ```
3. **Build & Run**
   - Choose the **TouchLyric** scheme.
   - Press **⌘R** – the menu‑bar icon appears.
   - When prompted, allow *Automation → Spotify* (required for AppleScript control).
4. **Install (optional)** – copy the built app bundle to your Applications folder:
   ```bash
   cp -R ~/Library/Developer/Xcode/DerivedData/TouchLyric-*/Build/Products/Debug/TouchLyric.app ~/Applications/TouchLyric.app
   ```
   You can now launch it from Launchpad or the Applications folder.

## ▶️ Usage

1. Start Spotify and play any track.
2. Click the **music‑note icon** in the menu bar – the pop‑over shows the current song, playback state, and a scrollable list of lyrics.
3. The **active line** (bold, accent colour) scrolls automatically to stay centered.
4. **Click a lyric line** to seek Spotify to that timestamp.
5. Use **‑0.5 s / +0.5 s** buttons to fine‑tune sync.
6. Toggle the **Touch Bar** button to show/hide the system‑wide lyric line.
7. **Quit** via the ❌ button in the pop‑over.

## 🧩 Extending the app

| Area | How to extend |
|------|---------------|
| **Settings UI** | Populate `SettingsView.swift` with `@AppStorage`‑backed options (offset default, cache size, theme). |
| **Multiple tracks** | Store a recent‑track list in `UserDefaults` and allow quick switching from the pop‑over. |
| **Unit tests** | Add a test target, mock `NSAppleScript` and `DistributedNotificationCenter` to verify timer scheduling. |
| **Code signing / notarisation** | Add a Developer ID certificate and run `codesign --deep --force -s "Developer ID Application: …" TouchLyric.app`. |
| **Distribution** | Build an exported `.pkg` or use `create-dmg` to bundle the app for other machines. |

## 📄 License

This project is released under the **MIT License** – feel free to fork, modify, and redistribute. See `LICENSE` for full text.

## 🙋‍♂️ Contributing

1. Fork the repository.
2. Create a feature branch (`git checkout -b my-feature`).
3. Commit your changes with clear messages.
4. Open a Pull Request describing the improvement.

All contributions are welcome, especially bug‑fixes, UI polish, and macOS‑specific enhancements.

## 🙏 Acknowledgements

- **Spotify** – for the public desktop client and AppleScript control interface.
- **lrclib.net** – free LRC lyric API.
- **Apple’s DFRFoundation** – private Touch Bar framework (used under the terms of macOS developer agreement).
- **SwiftUI** – for the modern, declarative UI.

Enjoy synchronized lyrics on your Touch Bar! 🎵