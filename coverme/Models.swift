//
//  Models.swift
//  coverme
//
//  Created by Mukil Chittybabu on 2/8/2025.
//

import Foundation
import SwiftUI

// MARK: - Spotify Models
public struct SpotifyTrack: Codable, Equatable {
    public let id: String
    public let name: String
    public let artist: String
    public let albumName: String
    public let albumImageURL: String?
    public let isPlaying: Bool
    public let progressMs: Int?
    public let durationMs: Int?
    
    public init(id: String, name: String, artist: String, albumName: String, albumImageURL: String?, isPlaying: Bool, progressMs: Int?, durationMs: Int?) {
        self.id = id
        self.name = name
        self.artist = artist
        self.albumName = albumName
        self.albumImageURL = albumImageURL
        self.isPlaying = isPlaying
        self.progressMs = progressMs
        self.durationMs = durationMs
    }
}

// MARK: - App Configuration Models
public enum WallpaperStyle: String, CaseIterable, Codable {
    case cover = "cover"
    case fit = "fit"
    case stretch = "stretch"
    case center = "center"
    case blurredBackground = "blurredBackground"
    case gradientFromAlbumColors = "gradientFromAlbumColors"
    case collageEffect = "collageEffect"
    case minimalistArt = "minimalistArt"
    
    public var displayName: String {
        switch self {
        case .cover: return "Cover"
        case .fit: return "Fit"
        case .stretch: return "Stretch"
        case .center: return "Center"
        case .blurredBackground: return "Blurred Background + Center Art"
        case .gradientFromAlbumColors: return "Gradient from Album Colors"
        case .collageEffect: return "Collage Effect with Previous Tracks"
        case .minimalistArt: return "Minimalist Art Mode"
        }
    }
}

public enum BackgroundFillMode: String, CaseIterable, Codable {
    case auto = "auto"
    case custom = "custom"
    
    public var displayName: String {
        switch self {
        case .auto: return "Auto (Dominant Color)"
        case .custom: return "Custom Color"
        }
    }
}

public enum RefreshRate: Int, CaseIterable, Codable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
    
    public var displayName: String {
        switch self {
        case .fiveSeconds: return "5 seconds"
        case .tenSeconds: return "10 seconds"
        case .thirtySeconds: return "30 seconds"
        }
    }
}