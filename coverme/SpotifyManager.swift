//
//  SpotifyManager.swift
//  coverme
//
//  Created by Mukil Chittybabu on 2/8/2025.
//

import Foundation
import Combine
import Security
import AppKit
import SwiftUI

class SpotifyManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentTrack: SpotifyTrack?
    @Published var authenticationError: String?

    // Load from environment variables
    private let clientID: String
    private let clientSecret: String
    private let redirectURI = "spotifywallpaper://callback"
    private let scopes = "user-read-currently-playing"

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpirationDate: Date?
    
    // Debouncing and rate limiting
    private var lastTrackUpdateTime: Date = Date.distantPast
    private var isUpdatingTrack = false
    private let minimumUpdateInterval: TimeInterval = 1.0 // 1 second minimum between updates

    private let keychainService = "com.coverme.spotify"
    private let accessTokenKey = "spotify_access_token"
    private let refreshTokenKey = "spotify_refresh_token"
    private let tokenExpirationKey = "spotify_token_expiration"

    init() {
        print("[SpotifyManager] Initializing SpotifyManager...")
        
        // Load Spotify credentials from environment variables
        self.clientID = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"] ?? "YOUR_SPOTIFY_CLIENT_ID"
        self.clientSecret = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_SECRET"] ?? "YOUR_SPOTIFY_CLIENT_SECRET"
        
        print("[SpotifyManager] Loaded clientID: \(clientID.prefix(10))...")
        print("[SpotifyManager] Loaded clientSecret: \(clientSecret.prefix(10))...")
        
        loadTokensFromKeychain()
        checkAuthenticationStatus()
        print("[SpotifyManager] Initialization complete. isAuthenticated: \(isAuthenticated)")
    }

    // MARK: - Authentication

    func authenticate() {
        print("[SpotifyManager] Starting authentication process...")
        guard clientID != "YOUR_SPOTIFY_CLIENT_ID" else {
            print("[SpotifyManager] ERROR: Please configure your Spotify Client ID")
            authenticationError = "Please configure your Spotify Client ID"
            return
        }

        let state = UUID().uuidString
        let authURL =
            "https://accounts.spotify.com/authorize?" + "client_id=\(clientID)&"
            + "response_type=code&"
            + "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&"
            + "scope=\(scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&"
            + "state=\(state)"

        if let url = URL(string: authURL) {
            print("[SpotifyManager] Opening authorization URL: \(url.absoluteString)")
            NSWorkspace.shared.open(url)
            print("[SpotifyManager] Waiting for OAuth callback...")
        }
    }

    func handleAuthCallback(url: URL) {
        print("[SpotifyManager] Received OAuth callback: \(url.absoluteString)")
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let queryItems = components.queryItems
        else {
            print("[SpotifyManager] ERROR: Invalid callback URL structure")
            authenticationError = "Invalid callback URL"
            return
        }

        print("[SpotifyManager] Parsing callback parameters: \(queryItems.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", "))")

        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            print("[SpotifyManager] ERROR: OAuth error received: \(error)")
            authenticationError = "Authentication failed: \(error)"
            return
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            print("[SpotifyManager] ERROR: No code or error found in callback")
            authenticationError = "No authorization code received"
            return
        }

        print("[SpotifyManager] Found authorization code, exchanging for tokens...")
        exchangeCodeForTokens(code: code)
    }

    private func exchangeCodeForTokens(code: String) {
        print("[SpotifyManager] Exchanging authorization code for access tokens...")
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(clientID):\(clientSecret)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)"
        request.httpBody = body.data(using: .utf8)

        print("[SpotifyManager] Making token exchange request to Spotify API...")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                print("[SpotifyManager] Token exchange response status: \(httpResponse.statusCode)")
            }
            DispatchQueue.main.async {
                self?.handleTokenResponse(data: data, error: error)
            }
        }.resume()
    }

    private func handleTokenResponse(data: Data?, error: Error?) {
        if let error = error {
            print("[SpotifyManager] ERROR: Network error during token exchange: \(error.localizedDescription)")
            authenticationError = "Token exchange failed: \(error.localizedDescription)"
            return
        }

        guard let data = data else {
            print("[SpotifyManager] ERROR: No data received from token exchange")
            authenticationError = "Invalid token response"
            return
        }

        print("[SpotifyManager] Received token response data (\(data.count) bytes)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("[SpotifyManager] Token response: \(responseString)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = json["access_token"] as? String
        else {
            print("[SpotifyManager] ERROR: Failed to parse token response")
            authenticationError = "Invalid token response"
            return
        }

        print("[SpotifyManager] Successfully parsed token response")
        print("[SpotifyManager] Access token received: \(accessToken.prefix(20))...")
        
        self.accessToken = accessToken
        self.refreshToken = json["refresh_token"] as? String
        
        if let refreshToken = self.refreshToken {
            print("[SpotifyManager] Refresh token received: \(refreshToken.prefix(20))...")
        }

        if let expiresIn = json["expires_in"] as? Int {
            print("[SpotifyManager] Token expires in: \(expiresIn) seconds")
            self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        }

        print("[SpotifyManager] Saving tokens to keychain...")
        saveTokensToKeychain()
        
        print("[SpotifyManager] Authentication successful! Setting isAuthenticated = true")
        isAuthenticated = true
        authenticationError = nil
        
        print("[SpotifyManager] Starting to fetch current track...")
        Task {
            await getCurrentlyPlayingTrack()
        }
    }

    // MARK: - API Calls

    func getCurrentlyPlayingTrack() async {
        // Check if we're already updating or if not enough time has passed
        let now = Date()
        if isUpdatingTrack || (now.timeIntervalSince(lastTrackUpdateTime) < minimumUpdateInterval) {
            print("[SpotifyManager] Skipping track update - too soon or already updating")
            return
        }
        
        isUpdatingTrack = true
        lastTrackUpdateTime = now
        
        await getCurrentlyPlayingTrackWithRetry(retryCount: 0)
        
        // Reset the updating flag after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isUpdatingTrack = false
        }
    }
    
    private func getCurrentlyPlayingTrackWithRetry(retryCount: Int) async {
        // print("[SpotifyManager] Fetching currently playing track...")
        guard let accessToken = accessToken else {
            print("[SpotifyManager] ERROR: No access token available")
            return
        }

        guard let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else {
            print("[SpotifyManager] ERROR: Invalid API URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                // print("[SpotifyManager] Currently playing API response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 401 {
                    print("[SpotifyManager] Token expired, attempting refresh...")
                    // Token expired, try to refresh
                    await refreshAccessToken()
                     return
                 }
 
                 if httpResponse.statusCode == 204 {
                     print("[SpotifyManager] No track currently playing")
                     // No track currently playing
                     DispatchQueue.main.async {
                         self.currentTrack = nil
                     }
                    return
                }
                
                if httpResponse.statusCode == 500 {
                    print("[SpotifyManager] Server error (500), retrying...")
                    if retryCount < 3 {
                        // Wait with exponential backoff: 1s, 2s, 4s
                        let delay = pow(2.0, Double(retryCount))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        await getCurrentlyPlayingTrackWithRetry(retryCount: retryCount + 1)
                        return
                    } else {
                        print("[SpotifyManager] Max retries reached for server error, giving up")
                        return
                    }
                }
                
                // Only proceed with parsing if we have a successful response (200)
                if httpResponse.statusCode != 200 {
                    print("[SpotifyManager] Unexpected response status: \(httpResponse.statusCode)")
                    return
                }
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let item = json["item"] as? [String: Any],
                let id = item["id"] as? String,
                let name = item["name"] as? String,
                let artists = item["artists"] as? [[String: Any]],
                let artist = artists.first?["name"] as? String,
                let album = item["album"] as? [String: Any],
                let images = album["images"] as? [[String: Any]]
            {

                let imageURL = images.sorted { ($0["width"] as? Int ?? 0) > ($1["width"] as? Int ?? 0) }.first?["url"] as? String

                let albumName = album["name"] as? String ?? ""
                let isPlaying = json["is_playing"] as? Bool ?? false
                let progressMs = json["progress_ms"] as? Int ?? 0
                let durationMs = item["duration_ms"] as? Int ?? 0

                let track = SpotifyTrack(
                    id: id,
                    name: name,
                    artist: artist,
                    albumName: albumName,
                    albumImageURL: imageURL,
                    isPlaying: isPlaying,
                    progressMs: progressMs,
                    durationMs: durationMs
                )

                DispatchQueue.main.async {
                    // Create a hash of the track's key properties for more reliable comparison
                    let currentTrackHash = self.currentTrack.map { track in
                        "\(track.id)|\(track.name)|\(track.artist)|\(track.albumName)|\(track.albumImageURL ?? "")|\(track.isPlaying)"
                    }
                    
                    let newTrackHash = "\(track.id)|\(track.name)|\(track.artist)|\(track.albumName)|\(track.albumImageURL ?? "")|\(track.isPlaying)"
                    
                    // Only update if the track has actually changed
                    if currentTrackHash != newTrackHash {
                        print("[SpotifyManager] Track changed: \(track.name) by \(track.artist)")
                        self.currentTrack = track
                    } else {
                        print("[SpotifyManager] Track unchanged, skipping update")
                    }
                }
            }
        } catch {
            print("Error fetching currently playing track: \(error)")
        }
    }

    private func refreshAccessToken() async {
        guard let refreshToken = refreshToken,
            let url = URL(string: "https://accounts.spotify.com/api/token")
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(clientID):\(clientSecret)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let newAccessToken = json["access_token"] as? String
            {
                print("[SpotifyManager] Successfully refreshed access token")
                self.accessToken = newAccessToken
                
                // Update expiration if provided
                if let expiresIn = json["expires_in"] as? Int {
                    self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
                    print("[SpotifyManager] Updated token expiration: \(self.tokenExpirationDate!)")
                }
                
                // Update refresh token if provided (some providers send a new one)
                if let newRefreshToken = json["refresh_token"] as? String {
                    self.refreshToken = newRefreshToken
                    print("[SpotifyManager] Updated refresh token")
                }
                
                // Save updated tokens to keychain
                self.saveTokensToKeychain()
                
                DispatchQueue.main.async {
                    self.isAuthenticated = true
                    self.authenticationError = nil
                }
            }
        } catch {
            print("Error refreshing token: \(error)")
        }
    }

    // MARK: - Keychain Management

    private func saveTokensToKeychain() {
        if let accessToken = accessToken {
            saveToKeychain(key: accessTokenKey, value: accessToken)
        }
        if let refreshToken = refreshToken {
            saveToKeychain(key: refreshTokenKey, value: refreshToken)
        }
        if let tokenExpirationDate = tokenExpirationDate {
            let expirationString = String(tokenExpirationDate.timeIntervalSince1970)
            saveToKeychain(key: tokenExpirationKey, value: expirationString)
        }
    }

    private func loadTokensFromKeychain() {
        accessToken = loadFromKeychain(key: accessTokenKey)
        refreshToken = loadFromKeychain(key: refreshTokenKey)
        
        if let expirationString = loadFromKeychain(key: tokenExpirationKey),
           let expirationInterval = Double(expirationString) {
            tokenExpirationDate = Date(timeIntervalSince1970: expirationInterval)
        }
    }

    private func saveToKeychain(key: String, value: String) {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
            let data = result as? Data,
            let string = String(data: data, encoding: .utf8)
        {
            return string
        }

        return nil
    }

    private func checkAuthenticationStatus() {
        let hasAccessToken = accessToken != nil
        let hasRefreshToken = refreshToken != nil
        let tokenValid = (tokenExpirationDate?.timeIntervalSinceNow ?? 0) > 300 // 5 minute buffer
        
        print("[SpotifyManager] Authentication status check:")
        print("[SpotifyManager] - Has access token: \(hasAccessToken)")
        print("[SpotifyManager] - Has refresh token: \(hasRefreshToken)")
        print("[SpotifyManager] - Token valid: \(tokenValid)")
        if let expiration = tokenExpirationDate {
            print("[SpotifyManager] - Token expires: \(expiration) (in \(expiration.timeIntervalSinceNow) seconds)")
        }
        
        // If we have tokens but access token is expired/expiring, try to refresh
        if hasRefreshToken && !tokenValid {
            print("[SpotifyManager] Access token expired but refresh token available, attempting refresh...")
            isAuthenticated = false // Temporarily set to false while refreshing
            Task {
                await refreshAccessToken()
            }
        } else {
            isAuthenticated = hasAccessToken && tokenValid
            print("[SpotifyManager] - Final isAuthenticated: \(isAuthenticated)")
        }
    }

    func logout() {
        print("[SpotifyManager] Logging out user...")
        accessToken = nil
        refreshToken = nil
        tokenExpirationDate = nil

        print("[SpotifyManager] Removing tokens from keychain...")
        // Clear keychain
        let accessQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: accessTokenKey,
        ]

        let refreshQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: refreshTokenKey,
        ]

        let expirationQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenExpirationKey,
        ]

        let accessDeleteResult = SecItemDelete(accessQuery as CFDictionary)
        let refreshDeleteResult = SecItemDelete(refreshQuery as CFDictionary)
        let expirationDeleteResult = SecItemDelete(expirationQuery as CFDictionary)
        print("[SpotifyManager] Access token keychain deletion result: \(accessDeleteResult)")
        print("[SpotifyManager] Refresh token keychain deletion result: \(refreshDeleteResult)")
        print("[SpotifyManager] Token expiration keychain deletion result: \(expirationDeleteResult)")

        isAuthenticated = false
        currentTrack = nil
        print("[SpotifyManager] Logout complete")
    }
}
