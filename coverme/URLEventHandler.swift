//
//  URLEventHandler.swift
//  coverme
//
//  Created by Mukil Chittybabu on 2/8/2025.
//

import Foundation
import AppKit

class URLEventHandler: NSObject {
    static let shared = URLEventHandler()
    var spotifyManager: SpotifyManager?
    
    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        print("[URLEventHandler] handleGetURLEvent called")
        
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            print("[URLEventHandler] ERROR: Could not extract URL string from event")
            print("[URLEventHandler] Event descriptor: \(event)")
            return
        }
        
        print("[URLEventHandler] Extracted URL string: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("[URLEventHandler] ERROR: Invalid URL format: \(urlString)")
            return
        }
        
        print("[URLEventHandler] Received URL event: \(url.absoluteString)")
        print("[URLEventHandler] URL scheme: \(url.scheme ?? "nil")")
        print("[URLEventHandler] URL host: \(url.host ?? "nil")")
        print("[URLEventHandler] URL path: \(url.path)")
        print("[URLEventHandler] URL query: \(url.query ?? "nil")")
        
        if url.scheme == "spotifywallpaper" {
            print("[URLEventHandler] Spotify callback detected, forwarding to SpotifyManager")
            if let manager = spotifyManager {
                print("[URLEventHandler] SpotifyManager is available, calling handleAuthCallback")
                manager.handleAuthCallback(url: url)
            } else {
                print("[URLEventHandler] ERROR: SpotifyManager is nil!")
            }
        } else {
            print("[URLEventHandler] URL scheme '\(url.scheme ?? "nil")' does not match 'spotifywallpaper'")
        }
    }
}