import SwiftUI
import Foundation
import AppKit

@main
struct CoverMeApp: App {
    @StateObject private var spotifyManager = SpotifyManager()
    @StateObject private var wallpaperManager = WallpaperManager()
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var statusItem: NSStatusItem?
    
    init() {
        print("[CoverMeApp] App initializing")
    }
    
    private func setupSpotifyManagerReference() {
        print("[CoverMeApp] Setting up SpotifyManager reference")
        URLEventHandler.shared.spotifyManager = spotifyManager
        AppDelegate.shared?.setSpotifyManager(spotifyManager)
    }
    
    private func startBackgroundService() {
        print("[CoverMeApp] Starting background service")
        // Trigger initial track fetch and wallpaper update
        Task {
            await spotifyManager.getCurrentlyPlayingTrack()
            if let track = spotifyManager.currentTrack {
                appState.currentTrack = track
                await wallpaperManager.updateWallpaper(
                    with: track,
                    style: appState.wallpaperStyle,
                    fillMode: appState.backgroundFillMode,
                    customColor: appState.customBackgroundColor
                )
            }
        }
    }
    
    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "CoverMe")
            button.action = #selector(AppDelegate.showMainWindow)
            button.target = AppDelegate.shared
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(spotifyManager)
                .environmentObject(wallpaperManager)
                .environmentObject(appState)
                .onAppear {
                    // Set up SpotifyManager reference and start background service immediately
                    setupSpotifyManagerReference()
                    setupStatusBarItem()
                    if appState.isServiceEnabled {
                        startBackgroundService()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    }
}
