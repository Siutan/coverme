//
//  MenuView.swift
//  coverme
//
//  Created by Mukil Chittybabu on 2/8/2025.
//

import SwiftUI
import Foundation

struct MenuView: View {
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var appState: AppState
    
    @State private var refreshTimer: Timer?
    @State private var lastTrackId: String?
    @State private var wallpaperUpdateTask: Task<Void, Never>?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current Track Info
            if let track = appState.currentTrack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("by \(track.artist)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.bottom, 4)
            } else {
                Text("No track playing")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            }
            
            Divider()
            
            // Service Toggle
            Toggle("Enable Wallpaper Service", isOn: Binding(
                get: { appState.isServiceEnabled },
                set: { newValue in
                    appState.isServiceEnabled = newValue
                    appState.savePreferences()
                    if newValue {
                        startRefreshTimer()
                    } else {
                        stopRefreshTimer()
                    }
                }
            ))
            
            // Wallpaper Style
            VStack(alignment: .leading, spacing: 4) {
                Text("Wallpaper Style")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Style", selection: Binding(
                    get: { appState.wallpaperStyle },
                    set: { newValue in
                        appState.wallpaperStyle = newValue
                        appState.savePreferences()
                        
                        // Apply wallpaper immediately if service is enabled and we have a current track
                        if appState.isServiceEnabled, let track = appState.currentTrack {
                            Task {
                                await wallpaperManager.updateWallpaper(
                                    with: track,
                                    style: newValue,
                                    fillMode: appState.backgroundFillMode,
                                    customColor: appState.customBackgroundColor
                                )
                            }
                        }
                    }
                )) {
                    ForEach(WallpaperStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            // Background Fill Mode
            VStack(alignment: .leading, spacing: 4) {
                Text("Background Fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Fill Mode", selection: Binding(
                    get: { appState.backgroundFillMode },
                    set: { newValue in
                        appState.backgroundFillMode = newValue
                        appState.savePreferences()
                        
                        // Apply wallpaper immediately if service is enabled and we have a current track
                        if appState.isServiceEnabled, let track = appState.currentTrack {
                            Task {
                                await wallpaperManager.updateWallpaper(
                                    with: track,
                                    style: appState.wallpaperStyle,
                                    fillMode: newValue,
                                    customColor: appState.customBackgroundColor
                                )
                            }
                        }
                    }
                )) {
                    ForEach(BackgroundFillMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            // Custom Color Picker (only show if custom mode is selected)
            if appState.backgroundFillMode == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Color")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ColorPicker("Background Color", selection: Binding(
                        get: { appState.customBackgroundColor },
                        set: { newValue in
                            appState.customBackgroundColor = newValue
                            appState.savePreferences()
                            
                            // Apply wallpaper immediately if service is enabled and we have a current track
                            if appState.isServiceEnabled, let track = appState.currentTrack {
                                Task {
                                    await wallpaperManager.updateWallpaper(
                                        with: track,
                                        style: appState.wallpaperStyle,
                                        fillMode: appState.backgroundFillMode,
                                        customColor: newValue
                                    )
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                }
            }
            
            // Refresh Rate
            VStack(alignment: .leading, spacing: 4) {
                Text("Refresh Rate")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Refresh Rate", selection: Binding(
                    get: { appState.refreshRate },
                    set: { newValue in
                        appState.refreshRate = newValue
                        appState.savePreferences()
                        if appState.isServiceEnabled {
                            startRefreshTimer()
                        }
                    }
                )) {
                    ForEach(RefreshRate.allCases, id: \.self) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            Divider()
            
            // Spotify Authentication
            if spotifyManager.isAuthenticated {
                Button("Logout from Spotify") {
                    spotifyManager.logout()
                    appState.isSpotifyAuthenticated = false
                    appState.currentTrack = nil
                    stopRefreshTimer()
                }
            } else {
                Button("Login to Spotify") {
                    spotifyManager.authenticate()
                }
            }
            
            // Error Display
            if let error = spotifyManager.authenticationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
            
            if let error = wallpaperManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
            
            // Processing Indicator
            if wallpaperManager.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Updating wallpaper...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            
            Divider()
            
            // Quit Button
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            if appState.isServiceEnabled {
                startRefreshTimer()
            }
        }
        .onDisappear {
            stopRefreshTimer()
        }
        .onChange(of: spotifyManager.isAuthenticated) { _, isAuthenticated in
            appState.isSpotifyAuthenticated = isAuthenticated
        }
        .onChange(of: spotifyManager.currentTrack) { _, track in
            appState.currentTrack = track
            
            // Cancel any existing wallpaper update task
            wallpaperUpdateTask?.cancel()
            
            // Update wallpaper if service is enabled and we have a new track
            // Only update if the track ID has actually changed to prevent duplicate updates
            if appState.isServiceEnabled, let track = track, track.id != lastTrackId {
                lastTrackId = track.id
                wallpaperUpdateTask = Task {
                    // Increased delay to prevent multiple updates per frame error
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    // Check if task was cancelled
                    guard !Task.isCancelled else { return }
                    
                    // Additional check to prevent concurrent updates
                    guard !wallpaperManager.isProcessing else { return }
                    
                    // Final check that track ID still matches to prevent stale updates
                    guard track.id == lastTrackId else { return }
                    
                    await wallpaperManager.updateWallpaper(
                        with: track,
                        style: appState.wallpaperStyle,
                        fillMode: appState.backgroundFillMode,
                        customColor: appState.customBackgroundColor
                    )
                }
            }
        }
    }
    
    private func startRefreshTimer() {
        stopRefreshTimer()
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(appState.refreshRate.rawValue), repeats: true) { _ in
            if spotifyManager.isAuthenticated {
                Task {
                    await spotifyManager.getCurrentlyPlayingTrack()
                }
            }
        }
        
        // Fetch immediately only if we don't have a current track
        if spotifyManager.isAuthenticated && spotifyManager.currentTrack == nil {
            Task {
                await spotifyManager.getCurrentlyPlayingTrack()
            }
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// Preview removed to resolve diagnostic scope issues