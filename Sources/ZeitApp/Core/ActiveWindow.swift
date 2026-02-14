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
    static func getFrontmostWindowBounds() throws -> WindowBounds {
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
            throw ActiveWindowError.appleScriptCreationFailed
        }

        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            let errorNumber = error[NSAppleScript.errorNumber] as? Int
            throw ActiveWindowError.appleScriptExecutionFailed(
                message: message,
                errorNumber: errorNumber,
                parentProcess: ProcessInfo.processInfo.processName
            )
        }

        guard let resultString = result.stringValue else {
            throw ActiveWindowError.noFrontmostWindow
        }

        let parts = resultString.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else {
            throw ActiveWindowError.unexpectedAppleScriptOutput(resultString)
        }

        return WindowBounds(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// Get which screen number (1-based) contains the active window
    static func getActiveScreenNumber() throws -> Int {
        let screens = NSScreen.screens

        // Single monitor — no need for AppleScript detection
        if screens.count <= 1 {
            return 1
        }

        let windowBounds = try getFrontmostWindowBounds()

        // Check which screen contains the window's top-left corner
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0

        for (index, screen) in screens.enumerated() {
            // Convert AppleScript coords (top-left origin, Y-down) to
            // NSScreen coords (bottom-left origin, Y-up)
            let convertedY = mainScreenHeight - CGFloat(windowBounds.y)
            let convertedPoint = CGPoint(x: CGFloat(windowBounds.x), y: convertedY)

            if screen.frame.contains(convertedPoint) {
                return index + 1
            }
        }

        // Fallback: check using window center
        let center = windowBounds.center
        let convertedCenterY = mainScreenHeight - CGFloat(center.y)
        let centerPoint = CGPoint(x: CGFloat(center.x), y: convertedCenterY)

        for (index, screen) in screens.enumerated() {
            if screen.frame.contains(centerPoint) {
                return index + 1
            }
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
            lines.append("  Frontmost window (AppleScript coords):")
            lines.append("    origin=(\(bounds.x),\(bounds.y)) size=\(bounds.width)x\(bounds.height)")
            lines.append("    center=(\(bounds.center.x),\(bounds.center.y))")

            let convertedTopLeftY = mainScreenHeight - CGFloat(bounds.y)
            let convertedCenterY = mainScreenHeight - CGFloat(bounds.center.y)
            lines.append("  Converted to NSScreen coords:")
            lines.append("    top-left=(\(bounds.x),\(Int(convertedTopLeftY)))")
            lines.append("    center=(\(bounds.center.x),\(Int(convertedCenterY)))")

            // Show which screen each point hits
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
            lines.append("  Frontmost window: not detected (AppleScript failed)")
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

// MARK: - Errors

enum ActiveWindowError: LocalizedError {
    case appleScriptCreationFailed
    case appleScriptExecutionFailed(message: String, errorNumber: Int?, parentProcess: String)
    case noFrontmostWindow
    case unexpectedAppleScriptOutput(String)
    case windowNotOnAnyScreen(ActiveWindow.WindowBounds)

    /// AppleScript error -1743 means the user denied the Automation permission prompt.
    /// Error -1728 often means System Events can't access UI elements (Accessibility).
    private static let permissionErrorNumbers: Set<Int> = [-1743, -1728, -10004]

    var errorDescription: String? {
        switch self {
        case .appleScriptCreationFailed:
            return "Failed to create AppleScript for window detection"

        case .appleScriptExecutionFailed(let message, let errorNumber, let parentProcess):
            let base = "AppleScript failed (error \(errorNumber.map(String.init) ?? "unknown")): \(message)"
            let processHint = "  Running as: \(parentProcess) (pid \(ProcessInfo.processInfo.processIdentifier))"

            if let num = errorNumber, Self.permissionErrorNumbers.contains(num) {
                return """
                \(base)
                \(processHint)
                  This looks like a permissions issue. The host app '\(parentProcess)' needs Automation access to "System Events".
                  Fix: System Settings > Privacy & Security > Automation > enable "System Events" for '\(parentProcess)'.
                  Note: permissions are per-app — Terminal.app, VS Code, and Zeit.app each need their own grant.
                """
            }

            return "\(base)\n\(processHint)"

        case .noFrontmostWindow:
            return "No frontmost window found (the frontmost app may have no open windows)"

        case .unexpectedAppleScriptOutput(let output):
            return "Unexpected AppleScript output: '\(output)'"

        case .windowNotOnAnyScreen(let bounds):
            return "Window at (\(bounds.x),\(bounds.y) \(bounds.width)x\(bounds.height)) could not be matched to any screen"
        }
    }
}
