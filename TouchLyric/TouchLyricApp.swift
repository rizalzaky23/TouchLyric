//
//  TouchLyricApp.swift
//  TouchLyric
//
//  Created by rizal-mac on 03/11/26.
//

import SwiftUI

@main
struct TouchLyricApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

