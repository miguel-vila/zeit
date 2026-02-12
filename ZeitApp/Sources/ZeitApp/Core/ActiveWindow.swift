import AppKit
import Foundation

/// Detects the active window and which screen it's on
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

    /// Get the frontmost window's position and size using AppleScript
    static func getFrontmostWindowBounds() -> WindowBounds? {
        let script = """
        tell application "System Events"
            set frontApp to first application process whose frontmost is true
            tell frontApp
                if (count of windows) > 0 then
                    set win to window 1
                    set winPos to position of win
                    set winSize to size of win
                    return (item 1 of winPos as text) & "," & (item 2 of winPos as text) & "," & (item 1 of winSize as text) & "," & (item 2 of winSize as text)
                end if
            end tell
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            return nil
        }

        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if error != nil {
            return nil
        }

        guard let resultString = result.stringValue else {
            return nil
        }

        let parts = resultString.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else {
            return nil
        }

        return WindowBounds(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// Get which screen number (1-based) contains the active window
    static func getActiveScreenNumber() -> Int {
        let screens = NSScreen.screens

        // Single monitor — no need for AppleScript detection
        if screens.count <= 1 {
            return 1
        }

        guard let windowBounds = getFrontmostWindowBounds() else {
            return 1  // Default to primary screen
        }

        // Check which screen contains the window's top-left corner
        for (index, screen) in screens.enumerated() {
            let frame = screen.frame

            // Convert window coordinates to screen coordinates
            // macOS uses bottom-left origin for screens
            let windowPoint = CGPoint(x: windowBounds.x, y: windowBounds.y)

            // Check if window origin is within this screen
            // Note: NSScreen.frame is in screen coordinates with origin at bottom-left
            // AppleScript returns coordinates with origin at top-left

            // Get the main screen's height to convert coordinate systems
            let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
            let convertedY = mainScreenHeight - CGFloat(windowBounds.y) - CGFloat(windowBounds.height)

            let convertedPoint = CGPoint(x: CGFloat(windowBounds.x), y: convertedY)

            if frame.contains(convertedPoint) {
                return index + 1
            }
        }

        // Fallback: check using window center
        let center = windowBounds.center
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let convertedCenterY = mainScreenHeight - CGFloat(center.y)
        let centerPoint = CGPoint(x: CGFloat(center.x), y: convertedCenterY)

        for (index, screen) in screens.enumerated() {
            if screen.frame.contains(centerPoint) {
                return index + 1
            }
        }

        return 1  // Default to primary screen
    }

    /// Get the frontmost application name
    static func getFrontmostAppName() -> String? {
        let script = """
        tell application "System Events"
            set frontApp to first application process whose frontmost is true
            return name of frontApp
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            return nil
        }

        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if error != nil {
            return nil
        }

        return result.stringValue
    }
}
