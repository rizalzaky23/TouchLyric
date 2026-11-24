//
//  TouchLyricTests.swift
//  TouchLyricTests
//
//  Created by rizal-mac on 03/11/26.
//

import Testing
import SwiftUI
@testable import TouchLyric

struct TouchLyricTests {

    @Test func appearancePersistsAndResets() {
        let suiteName = "TouchLyricTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appearance = TouchLyricAppearance(defaults: defaults)
        appearance.baseColorHex = "#AABBCC"
        appearance.activeColorHex = "#FF3366"
        appearance.fontChoice = .rounded
        appearance.fontWeight = .bold
        appearance.fontSize = 99 // should clamp to maxFontSize
        appearance.showMusicIcon = false

        let reloaded = TouchLyricAppearance(defaults: defaults)
        #expect(reloaded.baseColorHex == "#AABBCC")
        #expect(reloaded.activeColorHex == "#FF3366")
        #expect(reloaded.fontChoice == .rounded)
        #expect(reloaded.fontWeight == .bold)
        #expect(reloaded.fontSize == TouchLyricAppearance.maxFontSize)
        #expect(reloaded.showMusicIcon == false)

        reloaded.resetToDefaults()
        #expect(reloaded.baseColorHex == TouchLyricAppearance.defaultBaseHex)
        #expect(reloaded.activeColorHex == TouchLyricAppearance.defaultActiveHex)
        #expect(reloaded.fontChoice == .system)
        #expect(reloaded.fontWeight == .semibold)
        #expect(reloaded.fontSize == TouchLyricAppearance.defaultFontSize)
        #expect(reloaded.showMusicIcon == true)
    }

    @Test func colorHexRoundTripAndFallback() {
        let color = Color(hex: "#1CD661")
        #expect(color != nil)
        #expect(color?.toHex() == "#1CD661")
        #expect(Color(hex: "not-a-hex") == nil)
    }

}
