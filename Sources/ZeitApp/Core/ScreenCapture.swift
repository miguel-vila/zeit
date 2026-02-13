import AppKit
import CoreGraphics
import Foundation

/// Captures screenshots from all monitors using CoreGraphics
enum ScreenCapture {
    /// Capture all monitors and return paths to temporary PNG files
    /// - Returns: Dictionary mapping screen number (1-based) to file URL
    static func captureAllMonitors() throws -> [Int: URL] {
        var screenshots: [Int: URL] = [:]

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw ScreenCaptureError.noScreensFound
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeit_screenshots")

        // Ensure temp directory exists
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for (index, screen) in screens.enumerated() {
            let screenNumber = index + 1

            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }

            guard let image = CGDisplayCreateImage(displayID) else {
                continue
            }

            let filename = "screenshot_\(screenNumber)_\(timestamp).png"
            let fileURL = tempDir.appendingPathComponent(filename)

            try saveImage(image, to: fileURL)
            screenshots[screenNumber] = fileURL
        }

        guard !screenshots.isEmpty else {
            throw ScreenCaptureError.captureFailedAllScreens
        }

        return screenshots
    }

    /// Clean up screenshot files
    static func cleanup(screenshots: [Int: URL]) {
        for (_, url) in screenshots {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Save CGImage to PNG file
    private static func saveImage(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureError.destinationCreationFailed
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureError.imageWriteFailed
        }
    }

    /// Load image as base64 string for LLM, downscaled to reduce payload size
    /// CGDisplayCreateImage captures at retina resolution (2x-3x), but we want
    /// ~1280px max dimension to reduce payload size
    static func loadAsBase64(url: URL, maxDimension: Int = 1280) throws -> String {
        let data = try Data(contentsOf: url)

        guard let cgImageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) else {
            return data.base64EncodedString()
        }

        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height

        // Calculate scale factor to fit within maxDimension
        let scale = min(1.0, Double(maxDimension) / Double(max(pixelWidth, pixelHeight)))

        // If already small enough, just return the original
        if scale >= 1.0 {
            return data.base64EncodedString()
        }

        let newWidth = Int(Double(pixelWidth) * scale)
        let newHeight = Int(Double(pixelHeight) * scale)

        // Create a new CGContext for the resized image
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: newWidth,
                  height: newHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return data.base64EncodedString()
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let resizedCGImage = context.makeImage() else {
            return data.base64EncodedString()
        }

        // Convert to PNG data
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else {
            return data.base64EncodedString()
        }

        CGImageDestinationAddImage(destination, resizedCGImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return data.base64EncodedString()
        }

        return (mutableData as Data).base64EncodedString()
    }
}

// MARK: - Errors

enum ScreenCaptureError: LocalizedError {
    case noScreensFound
    case captureFailedAllScreens
    case destinationCreationFailed
    case imageWriteFailed

    var errorDescription: String? {
        switch self {
        case .noScreensFound:
            return "No screens found"
        case .captureFailedAllScreens:
            return "Failed to capture any screen"
        case .destinationCreationFailed:
            return "Failed to create image destination"
        case .imageWriteFailed:
            return "Failed to write image to file"
        }
    }
}
