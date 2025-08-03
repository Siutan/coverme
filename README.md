# CoverMe - Spotify Album Art Wallpaper Changer

A macOS menu bar application that automatically updates your wallpaper to match the album art of your currently playing Spotify track.

## Features

- **Multiple Wallpaper Styles**: Cover, Fit, Stretch, Center, and some more cool ones
- **Smart Background Colors**: Automatically extracts dominant colors from album art or use custom colors
- **Multi-Monitor Support**: Works across all connected displays (hopefully)
- **Customizable Refresh Rates**: 5, 10, or 30-second intervals

## Setup Instructions

### 1. Spotify API Configuration

Before using the app, you need to set up a Spotify application:

1. Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard/)
2. Click "Create App"
3. Fill in the details:
   - **App Name**: CoverMe (or any name you prefer)
   - **App Description**: Wallpaper changer for Spotify
   - **Redirect URI**: `spotifywallpaper://callback`
   - **API/SDKs**: Web API
4. Save the app and note down your **Client ID** and **Client Secret**
5. Replace the placeholder values:
   ```swift
   private let clientID = "YOUR_SPOTIFY_CLIENT_ID"        // Replace with your Client ID
   private let clientSecret = "YOUR_SPOTIFY_CLIENT_SECRET"  // Replace with your Client Secret
   ```
4. Build and run the app

### 3. First Time Usage

3. Click "Login to Spotify" to authenticate
4. Your browser will open - log in to Spotify and authorize the app
5. Return to the menu bar app and enable "Enable Wallpaper Service"

## How to Use
I'll add a proper one soon but for now...
Just open the app and it should be pretty self-explanatory.

### Current Track Display

The menu shows:
- Current track name
- Artist name
- "No track playing" when Spotify is paused/stopped

### Permissions

The app requires:
- **Network Access**: To communicate with Spotify API
- **File System Access**: To save temporary wallpaper files

## Future Enhancements

- Custom color picker improvements
- Per-monitor wallpaper settings
- Notification support

---

**Note**: This app is not affiliated with Spotify. Spotify is a trademark of Spotify AB.