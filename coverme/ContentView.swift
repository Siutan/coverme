//
//  ContentView.swift
//  coverme
//
//  Created by Mukil Chittybabu on 2/8/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var spotifyManager: SpotifyManager
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            // Background blur effect
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Title bar
                HStack {
                    Text("CoverMe")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Main content
                MenuView()
                    .environmentObject(spotifyManager)
                    .environmentObject(wallpaperManager)
                    .environmentObject(appState)
                    .background(Color.clear)
            }
        }
        .frame(width: 320, height: 400)
        .background(Color.clear)
    }
}

// Visual Effect View for blur background
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
