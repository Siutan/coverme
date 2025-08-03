//
//  AppState.swift
//  coverme
//
//  Created by Mukil Chittybabu on 2/8/2025.
//

import SwiftUI
import Foundation

class AppState: ObservableObject {
    @Published var isServiceEnabled: Bool = false
    @Published var wallpaperStyle: WallpaperStyle = .cover
    @Published var backgroundFillMode: BackgroundFillMode = .auto
    @Published var refreshRate: RefreshRate = .tenSeconds
    @Published var customBackgroundColor: Color = .black
    @Published var currentTrack: SpotifyTrack?
    @Published var isSpotifyAuthenticated: Bool = false
    
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadPreferences()
    }
    
    private func loadPreferences() {
        isServiceEnabled = userDefaults.bool(forKey: "isServiceEnabled")
        wallpaperStyle = WallpaperStyle(rawValue: userDefaults.string(forKey: "wallpaperStyle") ?? "cover") ?? .cover
        backgroundFillMode = BackgroundFillMode(rawValue: userDefaults.string(forKey: "backgroundFillMode") ?? "auto") ?? .auto
        refreshRate = RefreshRate(rawValue: userDefaults.integer(forKey: "refreshRate")) ?? .tenSeconds
        
        if let colorData = userDefaults.data(forKey: "customBackgroundColor"),
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customBackgroundColor = Color(nsColor)
        }
    }
    
    func savePreferences() {
        userDefaults.set(isServiceEnabled, forKey: "isServiceEnabled")
        userDefaults.set(wallpaperStyle.rawValue, forKey: "wallpaperStyle")
        userDefaults.set(backgroundFillMode.rawValue, forKey: "backgroundFillMode")
        userDefaults.set(refreshRate.rawValue, forKey: "refreshRate")
        
        let nsColor = NSColor(customBackgroundColor)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            userDefaults.set(colorData, forKey: "customBackgroundColor")
        }
    }
}
