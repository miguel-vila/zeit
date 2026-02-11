import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Permission checking for macOS Screen Recording and Accessibility
enum Permissions {
    // MARK: - Screen Recording

    /// Check if Screen Recording permission is granted
    /// Uses CGPreflightScreenCaptureAccess() which doesn't prompt the user
    static func checkScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Request Screen Recording permission
    /// This will show the system permission dialog
    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Accessibility

    /// Check if Accessibility permission is granted
    /// Uses AXIsProcessTrusted() which doesn't prompt the user
    static func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Request Accessibility permission with prompt
    /// Shows a system dialog directing user to System Settings
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - All Permissions

    /// Check if all required permissions are granted
    static func allGranted() -> Bool {
        checkScreenRecording() && checkAccessibility()
    }

    // MARK: - Open Settings

    /// System Settings URLs for privacy panes
    enum SettingsURL {
        static let screenRecording =
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        static let accessibility =
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    }

    /// Open System Settings to Screen Recording panel
    static func openScreenRecordingSettings() {
        if let url = URL(string: SettingsURL.screenRecording) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings to Accessibility panel
    static func openAccessibilitySettings() {
        if let url = URL(string: SettingsURL.accessibility) {
            NSWorkspace.shared.open(url)
        }
    }
}
