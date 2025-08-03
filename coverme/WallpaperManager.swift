import Foundation
import AppKit
import SwiftUI
import CoreGraphics
import CoreImage
import Darwin // For dlsym and dlopen

// MARK: - Dynamic Private API Loading from SkyLight
private let skylightHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

typealias CGSCopyActiveSpaceFunc = @convention(c) (UInt32) -> CFString
typealias CGSMainConnectionIDFunc = @convention(c) () -> UInt32

private var CGSCopyActiveSpace: CGSCopyActiveSpaceFunc? = {
    guard let sym = dlsym(skylightHandle, "CGSCopyActiveSpace") else { return nil }
    return unsafeBitCast(sym, to: CGSCopyActiveSpaceFunc.self)
}()

private var CGSMainConnectionID: CGSMainConnectionIDFunc? = {
    guard let sym = dlsym(skylightHandle, "CGSMainConnectionID") else { return nil }
    return unsafeBitCast(sym, to: CGSMainConnectionIDFunc.self)
}()

final class WallpaperManager: ObservableObject {
    @Published var isProcessing = false
    @Published var lastError: String?

    private var pendingWallpaperURLs: [Int: URL] = [:] // per-screen wallpapers
    private var spaceChangeObserver: NSObjectProtocol?
    private var trackHistory: [NSImage] = [] // Store previous album arts for collage effect
    private let maxHistoryCount = 20 // Reduced from 100 to 20 for memory optimization
    private var cleanupTimer: Timer?
    private var currentTrackImage: NSImage? // Keep reference to current track image
    private let maxCleanupHistoryCount = 15 // Keep reasonable number of images for collage
    private let maxTempFiles = 10 // Keep reasonable number of temp files

    init() {
        // Observe Space changes
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyWallpaperOnSpaceChange()
        }
        
        // Start cleanup timer for every 10 seconds
        startCleanupTimer()
    }

    deinit {
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        cleanupTimer?.invalidate()
        // Perform final cleanup on app close
        performCleanup()
    }

    // MARK: - Space Change Handling
    // Note: We've tried multiple approaches to detect the active space:
    // 1. SkyLight private APIs (CGSCopyActiveSpace) - often returns "unknown"
    // 2. Reading ~/Library/Preferences/com.apple.spaces.plist - complex parsing, not always current
    // 3. Various other macOS private APIs - unreliable or deprecated
    // 
    // Since reliable space detection is difficult, we now simply apply the wallpaper
    // to all screens whenever any space change is detected.
    
    // Called when Space changes - simply apply current wallpaper
    private func applyWallpaperOnSpaceChange() {
        print("[WallpaperManager] Space changed, applying current wallpaper")
        
        for screen in NSScreen.screens {
            if let wallpaperURL = pendingWallpaperURLs[screen.hash] {
                setWallpaper(imageURL: wallpaperURL, for: screen, syncAll: false)
            }
        }
    }

    // MARK: - Apply Wallpaper
    private func setWallpaper(imageURL: URL, for screen: NSScreen, syncAll: Bool) {
        do {
            let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                .allowClipping: true,
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue
            ]
            try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: options)

            if syncAll {
                applyWallpaperToAllSpaces(imageURL)
            }
        } catch {
            self.lastError = "Failed to set wallpaper: \(error.localizedDescription)"
            print("Failed to set wallpaper: \(error.localizedDescription)")
        }
    }

    /// Use AppleScript to update all Spaces at once (for initial sync)
    private func applyWallpaperToAllSpaces(_ imageURL: URL) {
        let script = """
            try
                tell application "System Events"
                    if running then
                        tell every desktop
                            set picture to "\(imageURL.path)"
                        end tell
                    end if
                end tell
            on error
                -- Ignore errors if System Events is unavailable
            end try
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // MARK: - Public API
    func updateWallpaper(with track: SpotifyTrack,
                         style: WallpaperStyle,
                         fillMode: BackgroundFillMode,
                         customColor: Color) async {
        guard let imageURLString = track.albumImageURL,
              let imageURL = URL(string: imageURLString) else {
            DispatchQueue.main.async {
                self.lastError = "Invalid album art URL"
            }
            return
        }

        // Cleanup old cached files when style changes (cached images are style-specific)
        performCleanup()

        DispatchQueue.main.async {
            self.isProcessing = true
            self.lastError = nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard let image = NSImage(data: data) else {
                DispatchQueue.main.async {
                    self.lastError = "Failed to create image from data"
                    self.isProcessing = false
                }
                return
            }

            for screen in NSScreen.screens {
                let processedImage = await processImage(image, for: screen, style: style, fillMode: fillMode, customColor: customColor, track: track)
                if let tempURL = saveImageToTemp(processedImage, screenIndex: screen.hash) {
                    DispatchQueue.main.async {
                        self.setWallpaper(imageURL: tempURL, for: screen, syncAll: true)
                        self.pendingWallpaperURLs[screen.hash] = tempURL
                    }
                }
            }

            DispatchQueue.main.async {
                self.isProcessing = false
            }
        } catch {
            DispatchQueue.main.async {
                self.lastError = "Failed to download image: \(error.localizedDescription)"
                self.isProcessing = false
            }
        }
    }

    // MARK: - Image Processing Helpers
    private func processImage(_ image: NSImage,
                               for screen: NSScreen,
                               style: WallpaperStyle,
                               fillMode: BackgroundFillMode,
                               customColor: Color,
                               track: SpotifyTrack) async -> NSImage {
        let screenSize = screen.frame.size
        // Update track history for collage effect
        updateTrackHistory(with: image)
        
        switch style {
        case .cover: return resizeImageToCover(image, targetSize: screenSize)
        case .fit:
            let bgColor = fillMode == .auto ? await ColorAnalyzer().dominantColor(from: image) : NSColor(customColor)
            return resizeImageToFit(image, targetSize: screenSize, backgroundColor: bgColor)
        case .stretch: return resizeImageToStretch(image, targetSize: screenSize)
        case .center:
            let bgColor = fillMode == .auto ? await ColorAnalyzer().dominantColor(from: image) : NSColor(customColor)
            return centerImage(image, targetSize: screenSize, backgroundColor: bgColor)
        case .blurredBackground:
            return WallpaperStyleRenderer.createBlurredBackgroundWallpaper(image, targetSize: screenSize)
        case .gradientFromAlbumColors:
            return WallpaperStyleRenderer.createGradientWallpaper(image, targetSize: screenSize)
        case .collageEffect:
            // Pass previous images (excluding current one which was just added)
            let previousImages = trackHistory.count > 1 ? Array(trackHistory.dropLast()) : []
            print("[COLLAGE DEBUG] Creating collage with \(previousImages.count) previous images")
            print("[COLLAGE DEBUG] Previous image sizes: \(previousImages.map { "\($0.size.width)x\($0.size.height)" })")
            print("[COLLAGE DEBUG] Current image size: \(image.size.width)x\(image.size.height)")
            print("[COLLAGE DEBUG] Target screen size: \(screenSize.width)x\(screenSize.height)")
            return WallpaperStyleRenderer.createCollageWallpaper(image, previousImages: previousImages, targetSize: screenSize)
        case .minimalistArt:
            return WallpaperStyleRenderer.createMinimalistWallpaper(image, trackName: track.name, artistName: track.artist, targetSize: screenSize)
        }
    }
    
    // MARK: - Track History Management
    private func updateTrackHistory(with image: NSImage) {
        // Resize image to smaller size for memory optimization (300x300 is sufficient for collage)
        let optimizedSize = NSSize(width: 300, height: 300)
        let optimizedImage = resizeImageForHistory(image, targetSize: optimizedSize)
        
        // Update current track image reference
        currentTrackImage = optimizedImage
        
        // Add optimized image to history
        trackHistory.append(optimizedImage)
        print("[COLLAGE DEBUG] Added optimized image to history. Current count: \(trackHistory.count)")
        
        // Keep only the last maxHistoryCount images
        if trackHistory.count > maxHistoryCount {
            let removedCount = trackHistory.count - maxHistoryCount
            trackHistory.removeFirst(removedCount)
            print("[COLLAGE DEBUG] Trimmed history. Removed \(removedCount) images. New count: \(trackHistory.count)")
        }
        
        print("[COLLAGE DEBUG] Track history sizes: \(trackHistory.map { "\($0.size.width)x\($0.size.height)" })")
    }
    
    private func resizeImageForHistory(_ image: NSImage, targetSize: NSSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        
        let sourceSize = image.size
        let aspectRatio = sourceSize.width / sourceSize.height
        let targetAspectRatio = targetSize.width / targetSize.height
        
        var drawRect: NSRect
        if aspectRatio > targetAspectRatio {
            // Image is wider, fit to height
            let newWidth = targetSize.height * aspectRatio
            drawRect = NSRect(x: (targetSize.width - newWidth) / 2, y: 0, width: newWidth, height: targetSize.height)
        } else {
            // Image is taller, fit to width
            let newHeight = targetSize.width / aspectRatio
            drawRect = NSRect(x: 0, y: (targetSize.height - newHeight) / 2, width: targetSize.width, height: newHeight)
        }
        
        image.draw(in: drawRect)
        newImage.unlockFocus()
        
        return newImage
    }
    
    private func resizeImageToCover(_ image: NSImage, targetSize: NSSize) -> NSImage {
        let imageSize = image.size
        let targetAspect = targetSize.width / targetSize.height
        let imageAspect = imageSize.width / imageSize.height
        var newSize: NSSize
        if imageAspect > targetAspect {
            newSize = NSSize(width: targetSize.height * imageAspect, height: targetSize.height)
        } else {
            newSize = NSSize(width: targetSize.width, height: targetSize.width / imageAspect)
        }
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        image.draw(in: NSRect(x: (targetSize.width - newSize.width) / 2,
                              y: (targetSize.height - newSize.height) / 2,
                              width: newSize.width,
                              height: newSize.height))
        newImage.unlockFocus()
        return newImage
    }

    private func resizeImageToFit(_ image: NSImage, targetSize: NSSize, backgroundColor: NSColor) -> NSImage {
        let imageSize = image.size
        let targetAspect = targetSize.width / targetSize.height
        let imageAspect = imageSize.width / imageSize.height
        var newSize: NSSize
        if imageAspect > targetAspect {
            newSize = NSSize(width: targetSize.width, height: targetSize.width / imageAspect)
        } else {
            newSize = NSSize(width: targetSize.height * imageAspect, height: targetSize.height)
        }
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        backgroundColor.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        image.draw(in: NSRect(x: (targetSize.width - newSize.width) / 2,
                              y: (targetSize.height - newSize.height) / 2,
                              width: newSize.width,
                              height: newSize.height))
        newImage.unlockFocus()
        return newImage
    }

    private func resizeImageToStretch(_ image: NSImage, targetSize: NSSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize))
        newImage.unlockFocus()
        return newImage
    }

    private func centerImage(_ image: NSImage, targetSize: NSSize, backgroundColor: NSColor) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        backgroundColor.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        image.draw(in: NSRect(x: (targetSize.width - image.size.width) / 2,
                              y: (targetSize.height - image.size.height) / 2,
                              width: image.size.width,
                              height: image.size.height))
        newImage.unlockFocus()
        return newImage
    }

    private func saveImageToTemp(_ image: NSImage, screenIndex: Int) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("coverme_wallpaper_\(screenIndex)_\(Date().timeIntervalSince1970).png")
        do {
            try pngData.write(to: tempURL)
            return tempURL
        } catch {
            print("Failed to save image to temp: \(error)")
            return nil
        }
    }
    
    // MARK: - Cleanup Management
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.performCleanup()
        }
    }
    
    private func performCleanup() {
        cleanupTemporaryFiles()
        cleanupTrackHistory()
    }
    
    private func cleanupTemporaryFiles() {
        let tempDirectory = FileManager.default.temporaryDirectory
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: [.creationDateKey], options: [])
            let covermeFiles = contents.filter { $0.lastPathComponent.hasPrefix("coverme_wallpaper_") }
            
            // Keep only the most recent files (for collage functionality)
            let sortedFiles = covermeFiles.sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }
            
            // Remove files beyond maxTempFiles limit
            if sortedFiles.count > maxTempFiles {
                for file in sortedFiles.dropFirst(maxTempFiles) {
                    try? FileManager.default.removeItem(at: file)
                    print("[CLEANUP] Removed old temp file: \(file.lastPathComponent)")
                }
                print("[CLEANUP] Kept \(min(sortedFiles.count, maxTempFiles)) most recent temp files")
            }
        } catch {
            print("[CLEANUP] Failed to cleanup temp files: \(error)")
        }
    }
    
    private func cleanupTrackHistory() {
        // Keep reasonable number of recent images for collage functionality
        if trackHistory.count > maxCleanupHistoryCount {
            let removedCount = trackHistory.count - maxCleanupHistoryCount
            trackHistory.removeFirst(removedCount)
            print("[CLEANUP] Trimmed track history from \(trackHistory.count + removedCount) to \(trackHistory.count) images")
        } else {
            print("[CLEANUP] Track history within limits: \(trackHistory.count) images")
        }
    }
}

// MARK: - ColorAnalyzer
class ColorAnalyzer {
    func dominantColor(from image: NSImage) async -> NSColor {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.extractDominantColor(from: image))
            }
        }
    }
    private func extractDominantColor(from image: NSImage) -> NSColor {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return .black }
        let sampleSize = 10
        let stepX = max(1, bitmap.pixelsWide / sampleSize)
        let stepY = max(1, bitmap.pixelsHigh / sampleSize)
        var r = 0, g = 0, b = 0, count = 0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
                if let color = bitmap.colorAt(x: x, y: y) {
                    r += Int(color.redComponent * 255)
                    g += Int(color.greenComponent * 255)
                    b += Int(color.blueComponent * 255)
                    count += 1
                }
            }
        }
        guard count > 0 else { return .black }
        return NSColor(red: CGFloat(r / count) / 255,
                       green: CGFloat(g / count) / 255,
                       blue: CGFloat(b / count) / 255,
                       alpha: 1)
    }
}
