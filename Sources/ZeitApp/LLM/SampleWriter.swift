#if DEBUG
import Foundation

enum SampleWriter {
    private static let samplesDir = ZeitConfig.dataDir.appendingPathComponent("samples")
    private static let maxAgeDays = 30

    /// Write sample data to ~/.local/share/zeit/samples/<timestamp>/
    /// Returns the URL of the created sample directory.
    @discardableResult
    static func write(_ data: SampleData) throws -> URL {
        let fm = FileManager.default

        // Format timestamp for directory name (dashes instead of colons for filesystem compat)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let dirName = formatter.string(from: data.timestamp)

        let sampleDir = samplesDir.appendingPathComponent(dirName)
        try fm.createDirectory(at: sampleDir, withIntermediateDirectories: true)

        // Copy screenshots
        for (index, screenshotURL) in data.screenshotURLs.enumerated() {
            let dest = sampleDir.appendingPathComponent("screen_\(index + 1).png")
            try fm.copyItem(at: screenshotURL, to: dest)
        }

        // Write vision.json
        let isoFormatter = ISO8601DateFormatter()
        let visionDict: [String: Any?] = [
            "timestamp": isoFormatter.string(from: data.timestamp),
            "active_screen": data.activeScreen,
            "frontmost_app": data.frontmostApp,
            "model": data.visionModel,
            "prompt": data.visionPrompt,
            "thinking": data.visionThinking,
            "response": data.visionResponse,
        ]
        let visionJSON = try JSONSerialization.data(
            withJSONObject: visionDict.compactMapValues { $0 },
            options: [.prettyPrinted, .sortedKeys]
        )
        try visionJSON.write(to: sampleDir.appendingPathComponent("vision.json"))

        // Write classification.json
        let classDict: [String: Any?] = [
            "model": data.classificationModel,
            "provider": data.classificationProvider,
            "prompt": data.classificationPrompt,
            "thinking": data.classificationThinking,
            "response": data.classificationResponse,
            "parsed_activity": data.parsedActivity,
            "parsed_reasoning": data.parsedReasoning,
        ]
        let classJSON = try JSONSerialization.data(
            withJSONObject: classDict.compactMapValues { $0 },
            options: [.prettyPrinted, .sortedKeys]
        )
        try classJSON.write(to: sampleDir.appendingPathComponent("classification.json"))

        // Best-effort cleanup of old samples
        try? cleanupOldSamples()

        return sampleDir
    }

    /// Delete sample directories older than 30 days.
    static func cleanupOldSamples() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: samplesDir.path) else { return }

        let contents = try fm.contentsOfDirectory(
            at: samplesDir,
            includingPropertiesForKeys: nil
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"

        let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date())!

        for dir in contents {
            guard dir.hasDirectoryPath else { continue }
            if let dirDate = formatter.date(from: dir.lastPathComponent),
               dirDate < cutoff
            {
                try? fm.removeItem(at: dir)
            }
        }
    }
}
#endif
