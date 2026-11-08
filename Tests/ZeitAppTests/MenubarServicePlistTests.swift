import Foundation
import Testing

@testable import ZeitApp

/// The menubar plist is what brings Zeit back after something kills it —
/// System Settings does, after a Screen Recording grant. launchd can only do
/// that if the app is launchd's own child, so the plist must name the
/// executable and never `open`, which exits as soon as it has launched the app
/// and leaves launchd with nothing to watch.
@Suite
struct MenubarServicePlistTests {
    private func installMenubarPlist() throws -> String {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Zeit.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/MacOS"),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: app.appendingPathComponent("Contents/MacOS/Zeit").path,
            contents: Data()
        )
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key><string>Zeit</string>
            <key>CFBundleIdentifier</key><string>co.invariante.zeit.test</string>
        </dict>
        </plist>
        """.write(
            to: app.appendingPathComponent("Contents/Info.plist"),
            atomically: true,
            encoding: .utf8
        )

        let agents = root.appendingPathComponent("LaunchAgents")
        let helper = ServiceHelper(launchAgentsDir: agents)
        try helper.installMenubarService(appPath: app.path)

        return try String(
            contentsOf: helper.plistPath(label: ServiceHelper.menubarLabel),
            encoding: .utf8
        )
    }

    @Test
    func launchdRunsTheExecutableItCanWatch() throws {
        let plist = try installMenubarPlist()

        #expect(plist.contains("Zeit.app/Contents/MacOS/Zeit</string>"))
        #expect(!plist.contains("/usr/bin/open"))
    }

    /// Unconditional, because a clean exit is how System Settings takes the
    /// app down. `SuccessfulExit` false would leave it down in exactly the
    /// case this is meant to cover.
    @Test
    func theJobIsKeptAliveWhateverTheExitCode() throws {
        let plist = try installMenubarPlist()

        #expect(plist.contains("<key>KeepAlive</key>\n    <true/>"))
        #expect(!plist.contains("SuccessfulExit"))
    }

    @Test
    func anAppPathWithNoBundleIsRefused() {
        let helper = ServiceHelper(
            launchAgentsDir: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
        )

        #expect(throws: ServiceError.self) {
            try helper.installMenubarService(appPath: "/nowhere/Zeit.app")
        }
    }
}
