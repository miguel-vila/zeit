import AppKit
import CoreGraphics
import Foundation

/// Where the System Settings window is on screen, so another window can follow
/// it around.
///
/// The window server reports the geometry of every on-screen window to anyone
/// who asks; only window titles and window images need Screen Recording. That
/// is what makes this usable while guiding the user through a grant Zeit does
/// not hold yet.
enum SystemSettingsWindow {
    private static let bundleIdentifier = "com.apple.systempreferences"

    /// The window frame in AppKit coordinates, emitted now and again on every
    /// tick, with `nil` while no System Settings window is on screen. The
    /// window server has no notification for another app's geometry, so this
    /// polls; the stream never finishes on its own.
    static func frames(every interval: Duration = .milliseconds(200)) -> AsyncStream<CGRect?> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                while !Task.isCancelled {
                    continuation.yield(currentFrame())
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The largest normal window belonging to System Settings, if it has one
    /// on screen. Matching on the bundle identifier rather than the window
    /// owner's name keeps this working in every language.
    @MainActor
    private static func currentFrame() -> CGRect? {
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleIdentifier }
            .map(\.processIdentifier)
        guard !pids.isEmpty else { return nil }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let bounds = windows.compactMap { window -> CGRect? in
            guard
                let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                pids.contains(pid),
                // Layer 0 is the normal window layer; panels and shadows sit elsewhere.
                window[kCGWindowLayer as String] as? Int == 0,
                let raw = window[kCGWindowBounds as String] as? [String: CGFloat],
                let rect = CGRect(dictionaryRepresentation: raw as CFDictionary)
            else { return nil }
            return rect
        }

        guard let largest = bounds.max(by: { $0.width * $0.height < $1.width * $1.height })
        else { return nil }

        return appKitFrame(quartzBounds: largest, primaryScreenHeight: primaryScreenHeight)
    }

    /// Height of the display that both coordinate spaces are anchored to: the
    /// one whose AppKit origin is zero.
    @MainActor
    private static var primaryScreenHeight: CGFloat {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        return primary?.frame.height ?? 0
    }

    /// The window server measures from the top of the primary display downward
    /// and AppKit from its bottom upward, so a frame has to be flipped to cross
    /// between them.
    static func appKitFrame(quartzBounds: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: quartzBounds.minX,
            y: primaryScreenHeight - quartzBounds.maxY,
            width: quartzBounds.width,
            height: quartzBounds.height
        )
    }
}
