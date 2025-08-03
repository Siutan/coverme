//
//  WallpaperStyles.swift
//  coverme
//
//  Created by Mukil Chittybabu on 2/8/2025.
//

import Foundation
import AppKit
import SwiftUI
import CoreGraphics
import CoreImage

// MARK: - Advanced Wallpaper Style Implementations
class WallpaperStyleRenderer {
    
    // MARK: - Blurred Background + Sharp Center Art
    static func createBlurredBackgroundWallpaper(_ image: NSImage, targetSize: NSSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        
        // Step 1: Create blurred, scaled-up background
        let blurredBackground = createBlurredBackground(image, targetSize: targetSize)
        blurredBackground.draw(in: NSRect(origin: .zero, size: targetSize))
        
        // Step 2: Calculate center art size (about 1/3 of screen width, maintaining aspect ratio)
        let centerArtMaxWidth = targetSize.width * 0.33
        let centerArtMaxHeight = targetSize.height * 0.5
        let centerArtSize = calculateFitSize(for: image.size, in: NSSize(width: centerArtMaxWidth, height: centerArtMaxHeight))
        
        // Step 3: Draw drop shadow
        let shadowOffset: CGFloat = 8
        let shadowBlur: CGFloat = 16
        let shadowRect = NSRect(
            x: (targetSize.width - centerArtSize.width) / 2,
            y: (targetSize.height - centerArtSize.height) / 2,
            width: centerArtSize.width,
            height: centerArtSize.height
        )
        
        drawDropShadow(in: shadowRect, offset: shadowOffset, blur: shadowBlur)
        
        // Step 4: Draw the crisp center art with rounded corners
        let centerRect = NSRect(
            x: (targetSize.width - centerArtSize.width) / 2,
            y: (targetSize.height - centerArtSize.height) / 2,
            width: centerArtSize.width,
            height: centerArtSize.height
        )
        
        drawRoundedImage(image, in: centerRect, cornerRadius: 12)
        
        newImage.unlockFocus()
        return newImage
    }
    
    // MARK: - Persistent Grid System for Efficient Collage
    private static var persistentGridState: CollageGridState?
    
    private struct CollageGridState {
        let cols: Int
        let rows: Int
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        let overlapFactor: CGFloat
        var occupiedPositions: Set<String> // "col,row" format
        var imagePositions: [ImagePosition] // Track all placed images
        let targetSize: NSSize
        
        struct ImagePosition {
            let col: Int
            let row: Int
            let centerX: CGFloat
            let centerY: CGFloat
            let rotation: CGFloat
            let width: CGFloat
            let height: CGFloat
            let isCurrentTrack: Bool
            let imageIndex: Int // Track which image this position corresponds to
        }
        
        init(targetSize: NSSize) {
            self.cols = 5
            self.rows = 4
            self.cellWidth = targetSize.width / CGFloat(self.cols)
            self.cellHeight = targetSize.height / CGFloat(self.rows)
            self.overlapFactor = 0.4
            self.occupiedPositions = Set<String>()
            self.imagePositions = []
            self.targetSize = targetSize
        }
        
        mutating func getNextAvailablePosition() -> (Int, Int)? {
            var availablePositions: [(Int, Int)] = []
            for row in 0..<rows {
                for col in 0..<cols {
                    let key = "\(col),\(row)"
                    if !occupiedPositions.contains(key) {
                        availablePositions.append((col, row))
                    }
                }
            }
            
            guard !availablePositions.isEmpty else { return nil }
            return availablePositions.randomElement()
        }
        
        mutating func addImagePosition(_ position: ImagePosition) {
            let key = "\(position.col),\(position.row)"
            occupiedPositions.insert(key)
            imagePositions.append(position)
        }
        
        mutating func reset() {
            occupiedPositions.removeAll()
            imagePositions.removeAll()
        }
        
        mutating func updateCurrentTrack() {
            // Remove existing current track
            if let currentTrackIndex = imagePositions.firstIndex(where: { $0.isCurrentTrack }) {
                let currentTrack = imagePositions[currentTrackIndex]
                let key = "\(currentTrack.col),\(currentTrack.row)"
                occupiedPositions.remove(key)
                imagePositions.remove(at: currentTrackIndex)
            }
        }
    }
    
    // Public method to reset grid when track changes
    static func resetCollageGrid() {
        persistentGridState?.reset()
        print("[COLLAGE DEBUG] Grid state reset for new session")
    }
    
    static func createCollageWallpaper(_ currentImage: NSImage, previousImages: [NSImage], targetSize: NSSize) -> NSImage {
        print("[COLLAGE DEBUG] Starting efficient photo collage creation with \(previousImages.count) previous images")
        print("[COLLAGE DEBUG] Target size: \(targetSize.width)x\(targetSize.height)")
        
        // Initialize or update persistent grid state
        if persistentGridState == nil || persistentGridState!.targetSize != targetSize {
            persistentGridState = CollageGridState(targetSize: targetSize)
            print("[COLLAGE DEBUG] Initialized new grid state")
        }
        
        guard var gridState = persistentGridState else { return currentImage }
        
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        
        // Step 1: Extract dominant colors and create background
        var allImages = [currentImage]
        allImages.append(contentsOf: previousImages)
        
        let backgroundColors = extractOptimalBackgroundColors(from: allImages)
        drawDiagonalGradient(colors: backgroundColors, in: NSRect(origin: .zero, size: targetSize))
        print("[COLLAGE DEBUG] Drew dynamic background gradient")
        
        // Step 2: Define polaroid properties
        let frameThickness: CGFloat = 12
        let bottomFrameExtra: CGFloat = 24
        
        // Step 3: Redraw all existing images from persistent state
        print("[COLLAGE DEBUG] Redrawing \(gridState.imagePositions.count) existing images from persistent state")
        for imagePos in gridState.imagePositions {
            let frameRect = NSRect(
                x: imagePos.centerX - imagePos.width / 2,
                y: imagePos.centerY - imagePos.height / 2,
                width: imagePos.width,
                height: imagePos.height
            )
            
            // Use the correct image based on stored index
            let imageToUse: NSImage
            if imagePos.isCurrentTrack {
                imageToUse = currentImage
            } else if imagePos.imageIndex < previousImages.count {
                imageToUse = previousImages[imagePos.imageIndex]
            } else {
                imageToUse = currentImage // Fallback
            }
            drawPolaroidFrame(imageToUse, in: frameRect, rotation: imagePos.rotation, frameThickness: frameThickness, bottomExtra: bottomFrameExtra, isCurrentTrack: imagePos.isCurrentTrack)
        }
        
        // Step 4: Add only new images that aren't already placed
        let existingImageCount = gridState.imagePositions.filter { !$0.isCurrentTrack }.count
        let newImagesToAdd = max(0, previousImages.count - existingImageCount)
        
        print("[COLLAGE DEBUG] Adding \(newImagesToAdd) new images to grid")
        
        for i in 0..<newImagesToAdd {
            guard let (col, row) = gridState.getNextAvailablePosition() else {
                print("[COLLAGE DEBUG] No more available positions")
                break
            }
            
            let imageIndex = existingImageCount + i
            guard imageIndex < previousImages.count else { break }
            
            let image = previousImages[imageIndex]
            
            // Calculate position
            let baseX = CGFloat(col) * gridState.cellWidth + gridState.cellWidth / 2
            let baseY = CGFloat(row) * gridState.cellHeight + gridState.cellHeight / 2
            
            let randomOffsetX = CGFloat.random(in: -gridState.cellWidth * 0.1...gridState.cellWidth * 0.1)
            let randomOffsetY = CGFloat.random(in: -gridState.cellHeight * 0.1...gridState.cellHeight * 0.1)
            
            let centerX = baseX + randomOffsetX
            let centerY = baseY + randomOffsetY
            
            let polaroidWidth = gridState.cellWidth * (1.1 + gridState.overlapFactor)
            let polaroidHeight = gridState.cellHeight * (1.1 + gridState.overlapFactor)
            let rotation = CGFloat.random(in: -20...20)
            
            // Create and store position
            let imagePosition = CollageGridState.ImagePosition(
                col: col,
                row: row,
                centerX: centerX,
                centerY: centerY,
                rotation: rotation,
                width: polaroidWidth,
                height: polaroidHeight,
                isCurrentTrack: false,
                imageIndex: imageIndex
            )
            
            gridState.addImagePosition(imagePosition)
            
            // Draw the new image
            let frameRect = NSRect(
                x: centerX - polaroidWidth / 2,
                y: centerY - polaroidHeight / 2,
                width: polaroidWidth,
                height: polaroidHeight
            )
            
            print("[COLLAGE DEBUG] Drawing new polaroid at grid (\(col),\(row)) with rotation \(rotation)°")
            drawPolaroidFrame(image, in: frameRect, rotation: rotation, frameThickness: frameThickness, bottomExtra: bottomFrameExtra)
        }
        
        // Step 5: Draw current track in center or prominent position
        let centerCol = gridState.cols / 2
        let centerRow = gridState.rows / 2
        let centerCellX = CGFloat(centerCol) * gridState.cellWidth + gridState.cellWidth / 2
        let centerCellY = CGFloat(centerRow) * gridState.cellHeight + gridState.cellHeight / 2
        
        // Make current track larger and more prominent, scaled for new grid
        let currentPolaroidWidth = gridState.cellWidth * 1.4
        let currentPolaroidHeight = gridState.cellHeight * 1.4
        
        let currentFrameRect = NSRect(
            x: centerCellX - currentPolaroidWidth / 2,
            y: centerCellY - currentPolaroidHeight / 2,
            width: currentPolaroidWidth,
            height: currentPolaroidHeight
        )
        
        print("[COLLAGE DEBUG] Drawing current track polaroid at center")
        
        // Add current track to persistent state if not already there
        let hasCurrentTrack = gridState.imagePositions.contains { $0.isCurrentTrack }
        if !hasCurrentTrack {
            let currentTrackPosition = CollageGridState.ImagePosition(
                col: centerCol,
                row: centerRow,
                centerX: centerCellX,
                centerY: centerCellY,
                rotation: 0,
                width: currentPolaroidWidth,
                height: currentPolaroidHeight,
                isCurrentTrack: true,
                imageIndex: -1 // Special index for current track
            )
            gridState.addImagePosition(currentTrackPosition)
        }
        
        // Draw current track with no rotation and extra glow
        drawPolaroidFrame(currentImage, in: currentFrameRect, rotation: 0, frameThickness: frameThickness * 1.5, bottomExtra: bottomFrameExtra * 1.5, isCurrentTrack: true)
        
        // Update persistent state
        persistentGridState = gridState
        
        print("[COLLAGE DEBUG] Photo collage creation completed successfully with \(gridState.imagePositions.count) total images")
        
        newImage.unlockFocus()
        return newImage
    }
    
    // MARK: - Gradient from Album Colors
    static func createGradientWallpaper(_ image: NSImage, targetSize: NSSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        
        // Step 1: Extract two dominant colors from the album art
        let dominantColors = extractDominantColors(from: image)
        
        // Step 2: Create gradient background (diagonal)
        drawDiagonalGradient(colors: dominantColors, in: NSRect(origin: .zero, size: targetSize))
        
        // Step 3: Calculate album art size (slightly smaller, about 25% of screen width)
        let artMaxWidth = targetSize.width * 0.25
        let artMaxHeight = targetSize.height * 0.4
        let artSize = calculateFitSize(for: image.size, in: NSSize(width: artMaxWidth, height: artMaxHeight))
        
        // Step 4: Position album art (slightly off-center for dynamic feel)
        let offsetX = targetSize.width * 0.1 // 10% offset from center
        let artRect = NSRect(
            x: (targetSize.width - artSize.width) / 2 + offsetX,
            y: (targetSize.height - artSize.height) / 2,
            width: artSize.width,
            height: artSize.height
        )
        
        // Step 5: Draw drop shadow
        let shadowOffset: CGFloat = 6
        let shadowBlur: CGFloat = 12
        drawDropShadow(in: artRect, offset: shadowOffset, blur: shadowBlur)
        
        // Step 6: Draw the album art with rounded corners
        drawRoundedImage(image, in: artRect, cornerRadius: 8)
        
        newImage.unlockFocus()
        return newImage
    }
    
    // MARK: - Minimalist Art Mode
    static func createMinimalistWallpaper(_ image: NSImage, trackName: String, artistName: String, targetSize: NSSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        
        // Step 1: Extract dominant color for solid background
        let dominantColors = extractDominantColors(from: image)
        let backgroundColor = dominantColors.first ?? NSColor.systemGray
        
        // Step 2: Fill background with dominant color
        backgroundColor.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        
        // Step 3: Calculate typography layout
        let centerX = targetSize.width / 2
        let centerY = targetSize.height / 2
        
        // Step 4: Draw track name (large, bold, centered)
        let trackFont = NSFont.systemFont(ofSize: min(targetSize.width * 0.08, 72), weight: .bold)
        let trackAttributes: [NSAttributedString.Key: Any] = [
            .font: trackFont,
            .foregroundColor: getContrastingTextColor(for: backgroundColor),
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                return style
            }()
        ]
        
        let trackString = NSAttributedString(string: trackName, attributes: trackAttributes)
        let trackSize = trackString.size()
        let trackRect = NSRect(
            x: centerX - trackSize.width / 2,
            y: centerY + 20,
            width: trackSize.width,
            height: trackSize.height
        )
        trackString.draw(in: trackRect)
        
        // Step 5: Draw artist name (smaller, below track name)
        let artistFont = NSFont.systemFont(ofSize: min(targetSize.width * 0.04, 36), weight: .medium)
        let artistAttributes: [NSAttributedString.Key: Any] = [
            .font: artistFont,
            .foregroundColor: getContrastingTextColor(for: backgroundColor).withAlphaComponent(0.8),
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                return style
            }()
        ]
        
        let artistString = NSAttributedString(string: artistName, attributes: artistAttributes)
        let artistSize = artistString.size()
        let artistRect = NSRect(
            x: centerX - artistSize.width / 2,
            y: centerY - 40,
            width: artistSize.width,
            height: artistSize.height
        )
        artistString.draw(in: artistRect)
        
        // Step 6: Draw small album art thumbnail in bottom right
        let thumbnailSize: CGFloat = min(targetSize.width * 0.12, 120)
        let thumbnailRect = NSRect(
            x: targetSize.width - thumbnailSize - 40,
            y: 40,
            width: thumbnailSize,
            height: thumbnailSize
        )
        
        // Add subtle shadow to thumbnail
        drawDropShadow(in: thumbnailRect, offset: 4, blur: 8)
        
        // Draw thumbnail with rounded corners
        drawRoundedImage(image, in: thumbnailRect, cornerRadius: 8)
        
        newImage.unlockFocus()
        return newImage
    }
    
    // MARK: - Helper Methods
    
    private static func isPositionInCenterArea(_ position: CGPoint, size: CGFloat, targetSize: NSSize) -> Bool {
        // Define center area to avoid (larger than the current track size)
        let centerAreaSize = min(targetSize.width * 0.35, targetSize.height * 0.5)
        let centerX = (targetSize.width - centerAreaSize) / 2
        let centerY = (targetSize.height - centerAreaSize) / 2
        let centerArea = NSRect(x: centerX, y: centerY, width: centerAreaSize, height: centerAreaSize)
        
        let imageRect = NSRect(x: position.x, y: position.y, width: size, height: size)
        return centerArea.intersects(imageRect)
    }
    
    private static func drawPolaroidFrame(_ image: NSImage, in rect: NSRect, rotation: CGFloat, frameThickness: CGFloat, bottomExtra: CGFloat, isCurrentTrack: Bool = false) {
        NSGraphicsContext.current?.saveGraphicsState()
        
        // Calculate rotation center
        let centerX = rect.midX
        let centerY = rect.midY
        
        // Apply rotation transform
        let transform = NSAffineTransform()
        transform.translateX(by: centerX, yBy: centerY)
        transform.rotate(byDegrees: rotation)
        transform.translateX(by: -centerX, yBy: -centerY)
        transform.concat()
        
        // Draw shadow for the entire polaroid
        let shadowContext = NSGraphicsContext.current?.cgContext
        let shadowOffset: CGFloat = isCurrentTrack ? 8 : 4
        let shadowBlur: CGFloat = isCurrentTrack ? 16 : 8
        shadowContext?.setShadow(
            offset: CGSize(width: shadowOffset * 0.3, height: -shadowOffset),
            blur: shadowBlur,
            color: NSColor.black.withAlphaComponent(isCurrentTrack ? 0.4 : 0.25).cgColor
        )
        
        // Draw white polaroid frame background
        let frameRect = rect
        let framePath = NSBezierPath(roundedRect: frameRect, xRadius: 4, yRadius: 4)
        NSColor.white.setFill()
        framePath.fill()
        
        // Calculate image area (inside the frame)
        let imageRect = NSRect(
            x: rect.minX + frameThickness,
            y: rect.minY + frameThickness + bottomExtra,
            width: rect.width - (frameThickness * 2),
            height: rect.height - (frameThickness * 2) - bottomExtra
        )
        
        // Create clipping path for the image area
        let imageClipPath = NSBezierPath(roundedRect: imageRect, xRadius: 2, yRadius: 2)
        imageClipPath.addClip()
        
        // Draw the image inside the frame
        image.draw(in: imageRect)
        
        // Add subtle aging effect if not current track
        if !isCurrentTrack {
            NSColor.systemYellow.withAlphaComponent(0.05).setFill()
            let overlayPath = NSBezierPath(roundedRect: imageRect, xRadius: 2, yRadius: 2)
            overlayPath.fill()
        }
        
        // Add extra glow for current track
        if isCurrentTrack {
            NSGraphicsContext.current?.saveGraphicsState()
            let glowPath = NSBezierPath(roundedRect: frameRect.insetBy(dx: -6, dy: -6), xRadius: 8, yRadius: 8)
            NSColor.white.withAlphaComponent(0.2).setFill()
            glowPath.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        
        NSGraphicsContext.current?.restoreGraphicsState()
    }
    
    private static func drawRotatedImageWithShadow(_ image: NSImage, in rect: NSRect, rotation: CGFloat, cornerRadius: CGFloat, shadowOffset: CGFloat, shadowBlur: CGFloat) {
        NSGraphicsContext.current?.saveGraphicsState()
        
        // Calculate rotation center
        let centerX = rect.midX
        let centerY = rect.midY
        
        // Apply rotation transform
        let transform = NSAffineTransform()
        transform.translateX(by: centerX, yBy: centerY)
        transform.rotate(byDegrees: rotation)
        transform.translateX(by: -centerX, yBy: -centerY)
        transform.concat()
        
        // Draw shadow first
        let shadowContext = NSGraphicsContext.current?.cgContext
        shadowContext?.setShadow(
            offset: CGSize(width: shadowOffset * 0.5, height: -shadowOffset),
            blur: shadowBlur,
            color: NSColor.black.withAlphaComponent(0.3).cgColor
        )
        
        // Create clipping path for rounded corners
        let clippingPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        clippingPath.addClip()
        
        // Draw the image
        image.draw(in: rect)
        
        NSGraphicsContext.current?.restoreGraphicsState()
    }
    
    private static func createBlurredBackground(_ image: NSImage, targetSize: NSSize) -> NSImage {
        // Create a scaled version that covers the entire screen
        let scaledImage = scaleImageToCover(image, targetSize: targetSize)
        
        // Apply blur using Core Image
        guard let tiffData = scaledImage.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return scaledImage
        }
        
        let blurFilter = CIFilter(name: "CIGaussianBlur")!
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(25.0, forKey: kCIInputRadiusKey) // Blur radius
        
        guard let blurredCIImage = blurFilter.outputImage else {
            return scaledImage
        }
        
        // Convert back to NSImage
        let context = CIContext()
        let cgImage = context.createCGImage(blurredCIImage, from: blurredCIImage.extent)!
        let blurredImage = NSImage(cgImage: cgImage, size: targetSize)
        
        return blurredImage
    }
    
    private static func scaleImageToCover(_ image: NSImage, targetSize: NSSize) -> NSImage {
        let imageSize = image.size
        let targetAspect = targetSize.width / targetSize.height
        let imageAspect = imageSize.width / imageSize.height
        
        var newSize: NSSize
        if imageAspect > targetAspect {
            // Image is wider than target - scale by height
            newSize = NSSize(width: targetSize.height * imageAspect, height: targetSize.height)
        } else {
            // Image is taller than target - scale by width
            newSize = NSSize(width: targetSize.width, height: targetSize.width / imageAspect)
        }
        
        let scaledImage = NSImage(size: targetSize)
        scaledImage.lockFocus()
        
        let drawRect = NSRect(
            x: (targetSize.width - newSize.width) / 2,
            y: (targetSize.height - newSize.height) / 2,
            width: newSize.width,
            height: newSize.height
        )
        
        image.draw(in: drawRect)
        scaledImage.unlockFocus()
        
        return scaledImage
    }
    
    private static func calculateFitSize(for imageSize: NSSize, in containerSize: NSSize) -> NSSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        if imageAspect > containerAspect {
            // Image is wider - fit by width
            let width = containerSize.width
            let height = width / imageAspect
            return NSSize(width: width, height: height)
        } else {
            // Image is taller - fit by height
            let height = containerSize.height
            let width = height * imageAspect
            return NSSize(width: width, height: height)
        }
    }
    
    private static func drawDropShadow(in rect: NSRect, offset: CGFloat, blur: CGFloat) {
        let shadowContext = NSGraphicsContext.current?.cgContext
        shadowContext?.saveGState()
        
        // Set shadow properties
        shadowContext?.setShadow(offset: CGSize(width: 0, height: -offset), blur: blur, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        
        // Draw a rounded rectangle for the shadow
        let shadowPath = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        NSColor.black.setFill()
        shadowPath.fill()
        
        shadowContext?.restoreGState()
    }
    
    private static func drawRoundedImage(_ image: NSImage, in rect: NSRect, cornerRadius: CGFloat) {
        // Save the current graphics state
        NSGraphicsContext.current?.saveGraphicsState()
        
        // Apply clipping path
        let clippingPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        clippingPath.addClip()
        
        // Draw the image
        image.draw(in: rect)
        
        // Restore the graphics state (removes the clipping path)
        NSGraphicsContext.current?.restoreGraphicsState()
    }
    
    // MARK: - Color Extraction and Gradient Methods
    
    private static func extractDominantColors(from image: NSImage) -> [NSColor] {
        // Convert NSImage to CGImage for color analysis
        guard let tiffData = image.tiffRepresentation,
              let imageRep = NSBitmapImageRep(data: tiffData),
              let cgImage = imageRep.cgImage else {
            // Fallback colors if extraction fails
            return [NSColor.systemBlue, NSColor.systemPurple]
        }
        
        // Use smaller sampling size for memory optimization (100x100 is sufficient for color analysis)
        let sampleSize = 100
        let _originalWidth = cgImage.width
        let _originalHeight = cgImage.height
        
        // Create smaller context for sampling
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * sampleSize
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: sampleSize * sampleSize * bytesPerPixel)
        
        guard let context = CGContext(data: &pixelData,
                                    width: sampleSize,
                                    height: sampleSize,
                                    bitsPerComponent: bitsPerComponent,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return [NSColor.systemBlue, NSColor.systemPurple]
        }
        
        // Draw scaled down image for sampling
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        
        // Sample colors from different regions with reduced resolution
        var colorCounts: [String: Int] = [:]
        let sampleStep = max(1, sampleSize / 20) // Sample every 20th pixel
        
        for y in stride(from: 0, to: sampleSize, by: sampleStep) {
            for x in stride(from: 0, to: sampleSize, by: sampleStep) {
                let pixelIndex = (y * sampleSize + x) * bytesPerPixel
                if pixelIndex + 3 < pixelData.count {
                    let r = pixelData[pixelIndex]
                    let g = pixelData[pixelIndex + 1]
                    let b = pixelData[pixelIndex + 2]
                    
                    // Group similar colors (reduce precision for clustering)
                    let colorKey = "\(r/32*32)-\(g/32*32)-\(b/32*32)"
                    colorCounts[colorKey, default: 0] += 1
                }
            }
        }
        
        // Get the two most common colors
        let sortedColors = colorCounts.sorted { $0.value > $1.value }
        var dominantColors: [NSColor] = []
        
        for (colorKey, _) in sortedColors.prefix(2) {
            let components = colorKey.split(separator: "-").compactMap { Int($0) }
            if components.count == 3 {
                let color = NSColor(red: CGFloat(components[0])/255.0,
                                  green: CGFloat(components[1])/255.0,
                                  blue: CGFloat(components[2])/255.0,
                                  alpha: 1.0)
                dominantColors.append(color)
            }
        }
        
        // Ensure we have at least 2 colors
        while dominantColors.count < 2 {
            dominantColors.append(dominantColors.isEmpty ? NSColor.systemBlue : NSColor.systemPurple)
        }
        
        return Array(dominantColors.prefix(2))
    }
    
    private static func averageHue(_ hues: [CGFloat]) -> CGFloat {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for h in hues {
            let θ = h * 2 * .pi
            sumX += cos(θ)
            sumY += sin(θ)
        }
        let avgθ = atan2(sumY, sumX)
        let positiveθ = avgθ < 0 ? avgθ + 2 * .pi : avgθ
        return positiveθ / (2 * .pi)
    }
    
    private static func extractOptimalBackgroundColors(from images: [NSImage]) -> [NSColor] {
        guard !images.isEmpty else {
            // Fallback to warm peachy colors if no images
            let peachColor1 = NSColor(red: 1.0, green: 0.85, blue: 0.7, alpha: 1.0)
            let peachColor2 = NSColor(red: 0.95, green: 0.8, blue: 0.65, alpha: 1.0)
            return [peachColor1, peachColor2]
        }
        
        // Collect all hue, saturation, brightness values with weighting
        var allHues = [CGFloat]()
        var allSaturations = [CGFloat]()
        var allBrightnesses = [CGFloat]()
        
        // Process each image with memory management
        return autoreleasepool {
            // Process each image, with the first image (current track) getting higher weight
            for (index, image) in images.enumerated() {
                autoreleasepool {
                    let dominantColors = extractDominantColors(from: image)
                    let topColors = Array(dominantColors.prefix(2)) // Take top 2 colors from each
                    
                    // Weight the current track (first image) 3x more than previous tracks
                    let weight = index == 0 ? 5 : 1
                    
                    for color in topColors {
                        var hue: CGFloat = 0
                        var saturation: CGFloat = 0
                        var brightness: CGFloat = 0
                        var alpha: CGFloat = 0
                        
                        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                        
                        // Add the color values multiple times based on weight
                        for _ in 0..<weight {
                            allHues.append(hue)
                            allSaturations.append(saturation)
                            allBrightnesses.append(brightness)
                        }
                    }
                }
            }
        
            print("[COLLAGE DEBUG] Extracted weighted colors from \(images.count) images (current track weighted 3x)")
            
            // If we have colors, analyze them to create a harmonious background
            if !allHues.isEmpty {
                // Properly average hue as circular data
                let avgHue = averageHue(allHues)
                
                // Average saturation/brightness with softer constraints
                let rawSaturation = allSaturations.reduce(0, +) / CGFloat(allSaturations.count)
                let rawBrightness = allBrightnesses.reduce(0, +) / CGFloat(allBrightnesses.count)
                let avgSaturation = min(max(rawSaturation, 0.2), 0.6) // Allow richer range
                let avgBrightness = min(max(rawBrightness, 0.7), 0.9) // Keep backgrounds bright but not blinding
                
                // Pick two harmonious hues; analogous ±30° (±0.0833)
                let hue1 = avgHue
                let hue2 = fmod(avgHue + 0.0833, 1.0)
                
                let color1 = NSColor(hue: hue1, saturation: avgSaturation, brightness: avgBrightness, alpha: 1.0)
                let color2 = NSColor(hue: hue2, saturation: avgSaturation, brightness: avgBrightness, alpha: 1.0)
                
                print("[COLLAGE DEBUG] Created background colors: \(color1), \(color2)")
                
                return [color1, color2]
            }
            
            // Fallback to warm peachy colors if no colors extracted, everyone likes peaches!
            let peachColor1 = NSColor(red: 1.0, green: 0.85, blue: 0.7, alpha: 1.0)
            let peachColor2 = NSColor(red: 0.95, green: 0.8, blue: 0.65, alpha: 1.0)
            return [peachColor1, peachColor2]
        }
    }
    
    private static func drawDiagonalGradient(colors: [NSColor], in rect: NSRect) {
        guard colors.count >= 2 else { return }
        
        let gradient = NSGradient(colors: colors)
        let startPoint = NSPoint(x: rect.minX, y: rect.maxY) // Top-left
        let endPoint = NSPoint(x: rect.maxX, y: rect.minY)   // Bottom-right
        
        gradient?.draw(from: startPoint, to: endPoint, options: [])
    }
    
    private static func getContrastingTextColor(for backgroundColor: NSColor) -> NSColor {
        // Convert to RGB color space if needed
        guard let rgbColor = backgroundColor.usingColorSpace(.deviceRGB) else {
            return NSColor.white
        }
        
        // Calculate luminance using the standard formula
        let red = rgbColor.redComponent
        let green = rgbColor.greenComponent
        let blue = rgbColor.blueComponent
        
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        
        // Return white text for dark backgrounds, black text for light backgrounds
        return luminance < 0.5 ? NSColor.white : NSColor.black
    }
}