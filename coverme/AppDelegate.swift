//
//  AppDelegate.swift
//  coverme
//
//  Created by Mukil Chittybabu on 2/8/2025.
//

import Foundation
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var spotifyManager: SpotifyManager?
    
    override init() {
        super.init()
        AppDelegate.shared = self
        print("[AppDelegate] AppDelegate initialized")
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] Setting up URL event handling in applicationWillFinishLaunching")
        
        // Register for URL events using NSAppleEventManager
        NSAppleEventManager.shared().setEventHandler(
            URLEventHandler.shared,
            andSelector: #selector(URLEventHandler.handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        
        print("[AppDelegate] URL event handler registered")
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] Application did finish launching")
        // The SpotifyManager should be set by now from the main app
        if let manager = spotifyManager {
            URLEventHandler.shared.spotifyManager = manager
            print("[AppDelegate] SpotifyManager reference set in URLEventHandler")
        } else {
            print("[AppDelegate] WARNING: SpotifyManager not yet available")
        }
    }
    
    func setSpotifyManager(_ manager: SpotifyManager) {
        print("[AppDelegate] Setting SpotifyManager reference")
        self.spotifyManager = manager
        URLEventHandler.shared.spotifyManager = manager
    }
    
    @objc func showMainWindow() {
        print("[AppDelegate] Showing main window")
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}