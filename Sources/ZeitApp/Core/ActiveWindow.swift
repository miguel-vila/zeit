import AppKit
import CoreGraphics
import Foundation

/// Detects the active window and which screen it's on.
/// Uses NSWorkspace + CGWindowList — no AppleScript, no System Events, no permissions.
enum ActiveWindow {
    struct WindowBounds {
        let x: Int
        let y: Int
        let width: Int
        let height: Int

        var center: (x: Int, y: Int) {
            (x + width / 2, y + height / 2)
        }
    }

    /// Get the frontmost window's position and size via CGWindowList.
    /// Coordinates are top-left origin, Y-down, anchored to the primary screen
    /// (same convention AppleScript used previously).
    static func getFrontmostWindowBounds() throws -> WindowBounds {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw ActiveWindowError.noFrontmostApp
        }
        let pid = frontApp.processIdentifier

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            throw ActiveWindowError.windowListUnavailable
        }

        // Windows are returned in front-to-back z-order. Pick the first normal-layer
        // (layer == 0) window owned by the frontmost app.
        let candidate = windowList.first { info in
            guard let ownerPid = info[kCGWindowOwnerPID as String] as? pid_t, ownerPid == pid else { return false }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return false }
            return true
        }

        guard let info = candidate,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict)
        else {
            throw ActiveWindowError.noFrontmostWindow
        }

        return WindowBounds(
            x: Int(bounds.origin.x),
            y: Int(bounds.origin.y),
            width: Int(bounds.size.width),
            height: Int(bounds.size.height)
        )
    }

    /// Get which screen number (1-based) contains the active window
    static func getActiveScreenNumber() throws -> Int {
        let screens = NSScreen.screens

        // Single monitor — no need to look at window geometry.
        if screens.count <= 1 {
            return 1
        }

        let windowBounds = try getFrontmostWindowBounds()
        let mainScreenHeight = screens.first?.frame.height ?? 0

        // Convert CGWindowList coords (top-left origin, Y-down) to
        // NSScreen coords (bottom-left origin, Y-up).
        let convertedY = mainScreenHeight - CGFloat(windowBounds.y)
        let topLeft = CGPoint(x: CGFloat(windowBounds.x), y: convertedY)

        for (index, screen) in screens.enumerated() where screen.frame.contains(topLeft) {
            return index + 1
        }

        // Fallback: use the window's center point.
        let center = windowBounds.center
        let convertedCenterY = mainScreenHeight - CGFloat(center.y)
        let centerPoint = CGPoint(x: CGFloat(center.x), y: convertedCenterY)

        for (index, screen) in screens.enumerated() where screen.frame.contains(centerPoint) {
            return index + 1
        }

        throw ActiveWindowError.windowNotOnAnyScreen(windowBounds)
    }

    /// Collect debug info about screen detection inputs and results
    static func getScreenDebugInfo() -> String {
        let screens = NSScreen.screens
        let mainScreenHeight = screens.first?.frame.height ?? 0
        var lines: [String] = []

        lines.append("Screen detection debug info:")
        lines.append("  Screens: \(screens.count)")
        lines.append("  Primary screen height: \(Int(mainScreenHeight))")

        for (index, screen) in screens.enumerated() {
            let f = screen.frame
            lines.append("  Screen \(index + 1): frame=(\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height)))" +
                         (index == 0 ? " [primary]" : ""))
        }

        if let bounds = try? getFrontmostWindowBounds() {
            lines.append("  Frontmost window (CGWindowList coords):")
            lines.append("    origin=(\(bounds.x),\(bounds.y)) size=\(bounds.width)x\(bounds.height)")
            lines.append("    center=(\(bounds.center.x),\(bounds.center.y))")

            let convertedTopLeftY = mainScreenHeight - CGFloat(bounds.y)
            let convertedCenterY = mainScreenHeight - CGFloat(bounds.center.y)
            lines.append("  Converted to NSScreen coords:")
            lines.append("    top-left=(\(bounds.x),\(Int(convertedTopLeftY)))")
            lines.append("    center=(\(bounds.center.x),\(Int(convertedCenterY)))")

            for (index, screen) in screens.enumerated() {
                let topLeftHit = screen.frame.contains(CGPoint(x: CGFloat(bounds.x), y: convertedTopLeftY))
                let centerHit = screen.frame.contains(CGPoint(x: CGFloat(bounds.center.x), y: convertedCenterY))
                if topLeftHit || centerHit {
                    var hits: [String] = []
                    if topLeftHit { hits.append("top-left") }
                    if centerHit { hits.append("center") }
                    lines.append("    -> Screen \(index + 1) matched by: \(hits.joined(separator: ", "))")
                }
            }
        } else {
            lines.append("  Frontmost window: not detected")
        }

        if let appName = getFrontmostAppName() {
            lines.append("  Frontmost app: \(appName)")
        }

        if let screen = try? getActiveScreenNumber() {
            lines.append("  Result: Screen \(screen)")
        } else {
            lines.append("  Result: FAILED")
        }

        return lines.joined(separator: "\n")
    }

    /// Get the frontmost application name
    static func getFrontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}

// MARK: - Errors

enum ActiveWindowError: LocalizedError {
    case noFrontmostApp
    case windowListUnavailable
    case noFrontmostWindow
    case windowNotOnAnyScreen(ActiveWindow.WindowBounds)

    var errorDescription: String? {
        switch self {
        case .noFrontmostApp:
            return "No frontmost application is currently active"

        case .windowListUnavailable:
            return "CGWindowListCopyWindowInfo returned no data"

        case .noFrontmostWindow:
            return "No frontmost window found (the frontmost app may have no open windows)"

        case .windowNotOnAnyScreen(let bounds):
            return "Window at (\(bounds.x),\(bounds.y) \(bounds.width)x\(bounds.height)) could not be matched to any screen"
        }
    }
}
