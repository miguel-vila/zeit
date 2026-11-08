import ArgumentParser
import Foundation

/// System diagnostics command
struct DoctorCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check system configuration"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        var checks: [Check] = []

        // Model checks: the active vision + text models from the config.
        let config = ZeitConfig.load()
        let visionInfo = MLXModelManager.modelInfo(forConfigName: config.models.vision)
            ?? MLXModelManager.visionModel
        checks.append(await checkLocalModel(visionInfo))
        if config.models.text.provider.lowercased() == "mlx" {
            let textInfo = MLXModelManager.modelInfo(forConfigName: config.models.text.model)
                ?? MLXModelManager.textModel
            checks.append(await checkLocalModel(textInfo))
        }

        // Schedule: when this machine tracks, and whether it is tracking now.
        // Being outside the schedule is not a failure, so this check passes
        // either way.
        let scheduleForm = config.schedule == .always
            ? config.schedule.formDescription
            : "\(config.schedule.formDescription) (\(config.schedule.summary))"
        checks.append(Check(
            name: "Schedule",
            passed: true,
            details: "\(scheduleForm) — "
                + (config.schedule.contains(Date()) ? "tracking now" : "not tracking now")
        ))

        // Cadence: how often this machine tracks, whether it holds off on
        // battery, and what this tick would do. Holding off is not a failure
        // either, so this check also passes both ways.
        let decision = await CLITrackingHelper().decideTick()
        checks.append(Check(
            name: "Tracking cadence",
            passed: true,
            details: "every \(config.tracking.intervalSeconds)s, "
                + "skip on battery: \(config.tracking.skipOnBattery ? "on" : "off") — "
                + (decision.skipReason.map { "this tick would skip: \($0)" }
                    ?? "this tick would track")
        ))

        // Classification: the group this machine is judged by.
        checks.append(Check(
            name: "Primary group",
            passed: true,
            details: "\(config.classification.primaryGroup.rawValue) "
                + "(\(config.classification.primaryGroup.displayName))"
        ))

        // Permission checks
        checks.append(contentsOf: Permission.allCases.map(checkPermission))

        // Data directory checks
        checks.append(checkDataDirectory())
        checks.append(checkDatabaseFile())
        checks.append(checkLogDirectory())

        // Service checks
        let helper = ServiceHelper()
        checks.append(Check(
            name: "Tracker LaunchAgent",
            passed: helper.plistExists(label: ServiceHelper.trackerLabel),
            details: helper.plistExists(label: ServiceHelper.trackerLabel)
                ? helper.plistPath(label: ServiceHelper.trackerLabel).path
                : "Not installed"
        ))
        checks.append(Check(
            name: "Menubar LaunchAgent",
            passed: helper.plistExists(label: ServiceHelper.menubarLabel),
            details: helper.plistExists(label: ServiceHelper.menubarLabel)
                ? helper.plistPath(label: ServiceHelper.menubarLabel).path
                : "Not installed"
        ))
        checks.append(Check(
            name: "Tracker service",
            passed: helper.isServiceLoaded(label: ServiceHelper.trackerLabel),
            details: helper.isServiceLoaded(label: ServiceHelper.trackerLabel) ? "Running" : "Not running"
        ))
        checks.append(Check(
            name: "Menubar service",
            passed: helper.isServiceLoaded(label: ServiceHelper.menubarLabel),
            details: helper.isServiceLoaded(label: ServiceHelper.menubarLabel) ? "Running" : "Not running"
        ))

        let allPassed = checks.allSatisfy { $0.passed }

        // What the tracker has actually been storing. A readout rather than a
        // check: a sample is evidence, and a thin window or an odd gap is for
        // the reader to judge, so none of this can fail `doctor`.
        let samples = await recentSamples()

        if json {
            try printJSON(checks: checks, samples: samples, allPassed: allPassed)
        } else {
            printTable(checks: checks, allPassed: allPassed)
            printSamples(samples)
        }

        if !allPassed {
            throw ExitCode(1)
        }
    }

    /// The sample window, empty when the database cannot be read.
    ///
    /// `doctor` runs to tell someone why Zeit is unwell, so a database it
    /// cannot open must still produce the rest of the report: the other checks
    /// are what would explain the failure.
    private func recentSamples() async -> [TrackingSample] {
        guard let db = try? DatabaseHelper() else { return [] }

        let knownTypeIDs = Set(
            ((try? await db.getActivityTypes()) ?? []).map(\.id)
        )
        let entries = (try? await db.recentEntries(limit: Self.sampleWindow)) ?? []

        return RecentSamples.from(
            entries: entries,
            knownTypeIDs: knownTypeIDs,
            limit: Self.sampleWindow
        )
    }

    /// Enough samples to show the cadence and any recent drift, while still
    /// fitting on a screen next to the checks.
    private static let sampleWindow = 20

    // MARK: - Check Functions

    private func checkLocalModel(_ model: MLXModelInfo) async -> Check {
        let isDownloaded = await MLXModelManager.shared.isModelDownloaded(model: model)
        return Check(
            name: "Model: \(model.displayName)",
            passed: isDownloaded,
            details: isDownloaded
                ? "Downloaded (\(model.huggingFaceID))"
                : "Not downloaded - use the app's onboarding or download via the menubar"
        )
    }

    private func checkPermission(_ permission: Permission) -> Check {
        let hasPermission = permission.isGranted
        return Check(
            name: "Permission: \(permission.displayName)",
            passed: hasPermission,
            details: hasPermission ? "Granted" : "Open: \(permission.settingsURL.absoluteString)"
        )
    }

    private func checkDataDirectory() -> Check {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/zeit")
        let exists = FileManager.default.fileExists(atPath: path.path)
        return Check(
            name: "Data directory",
            passed: exists,
            details: exists ? path.path : "Not found"
        )
    }

    private func checkDatabaseFile() -> Check {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/zeit/zeit.db")
        let exists = FileManager.default.fileExists(atPath: path.path)
        return Check(
            name: "Database file",
            passed: exists,
            details: exists ? path.path : "Not found"
        )
    }

    private func checkLogDirectory() -> Check {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/zeit")
        let exists = FileManager.default.fileExists(atPath: path.path)
        return Check(
            name: "Log directory",
            passed: exists,
            details: exists ? path.path : "Not found"
        )
    }

    // MARK: - Output

    private func printJSON(
        checks: [Check],
        samples: [TrackingSample],
        allPassed: Bool
    ) throws {
        struct Sample: Encodable {
            let timestamp: String
            let activity: String
            let knownType: Bool
            let device: String?
            let sincePreviousSeconds: Int?

            enum CodingKeys: String, CodingKey {
                case timestamp
                case activity
                case knownType = "known_type"
                case device
                case sincePreviousSeconds = "since_previous_seconds"
            }
        }

        struct Output: Encodable {
            let checks: [Check]
            let recentSamples: [Sample]
            let medianGapSeconds: Int?
            let allPassed: Bool

            enum CodingKeys: String, CodingKey {
                case checks
                case recentSamples = "recent_samples"
                case medianGapSeconds = "median_gap_seconds"
                case allPassed = "all_passed"
            }
        }

        let formatter = ISO8601DateFormatter()
        let output = Output(
            checks: checks,
            recentSamples: samples.map { sample in
                Sample(
                    timestamp: formatter.string(from: sample.timestamp),
                    activity: sample.activity.rawValue,
                    knownType: sample.isKnownType,
                    device: sample.device,
                    sincePreviousSeconds: sample.sincePrevious.map { Int($0.rounded()) }
                )
            },
            medianGapSeconds: RecentSamples.medianGap(of: samples)
                .map { Int($0.rounded()) },
            allPassed: allPassed
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)
        print(String(data: data, encoding: .utf8)!)
    }

    private func printTable(checks: [Check], allPassed: Bool) {
        print("Zeit System Check")
        print("=" .repeated(60))
        print("")

        for check in checks {
            let status = check.passed ? "✓" : "✗"
            print("\(status) \(check.name)")
            print("    \(check.details)")
        }

        print("")
        if allPassed {
            print("All checks passed!")
        } else {
            print("Some checks failed. See details above.")
        }
    }

    /// The sample window, newest first.
    ///
    /// Each line is one stored entry: when it was captured, how long since the
    /// entry before it, the type it names, and the machine that wrote it. The
    /// gap is what makes a cadence problem visible — the configured interval is
    /// a request, and this column is what the tracker managed.
    private func printSamples(_ samples: [TrackingSample]) {
        print("")
        print("Recent samples (newest first)")
        print("=".repeated(60))
        print("")

        guard !samples.isEmpty else {
            print("No entries stored yet.")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"

        for sample in samples {
            let gap = sample.sincePrevious
                .map { "+\(Int($0.rounded()))s" } ?? "—"
            let unknown = sample.isKnownType ? "" : "  (type not in catalog)"
            print(
                "  \(formatter.string(from: sample.timestamp))"
                    + "  \(gap.padded(to: 7))"
                    + "  \(sample.activity.rawValue.padded(to: 26))"
                    + "\(sample.device ?? "unknown device")\(unknown)"
            )
        }

        print("")
        if let median = RecentSamples.medianGap(of: samples) {
            print("Median gap: \(Int(median.rounded()))s over \(samples.count) samples")
        }

        let unknownCount = samples.filter { !$0.isKnownType }.count
        if unknownCount > 0 {
            print(
                "\(unknownCount) of \(samples.count) name a type the catalog "
                    + "no longer defines, and read as unclassified."
            )
        }
    }
}

// MARK: - Check Model

struct Check: Encodable {
    let name: String
    let passed: Bool
    let details: String
}
