import Foundation
import GRDB
import Testing
import Yams

@testable import ZeitApp

/// A calendar that puts a timestamp on the same day wherever the tests run.
private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// `device.name` is display only and always resolves to something: a name from
/// the config, or this machine's name. Parsing goes through
/// `ZeitConfig.parse(yaml:)` so the tests never touch the config file on disk.
@Suite
struct DeviceConfigTests {
    private func config(_ yaml: String) throws -> ZeitConfig {
        let parsed = try Yams.load(yaml: yaml) as? [String: Any] ?? [:]
        return ZeitConfig.parse(yaml: parsed)
    }

    @Test
    func theNameIsReadFromTheConfig() throws {
        let parsed = try config(
            """
            device:
              name: 'Work MBP'
            """
        )

        #expect(parsed.device.name == "Work MBP")
    }

    /// Every existing install: no `device:` block at all.
    @Test
    func aConfigWithoutADeviceBlockUsesTheHostNameAndKeepsTheRest() throws {
        let parsed = try config(
            """
            classification:
              primary_group: 'personal_projects'

            models:
              vision: 'qwen3-vl:8b'
            """
        )

        #expect(parsed.device.name == ZeitConfig.DeviceConfig.hostName)
        #expect(parsed.classification.primaryGroup == .personalProjects)
        #expect(parsed.models.vision == "qwen3-vl:8b")
    }

    /// A blank name would stamp entries with nothing, which is worse than the
    /// default it replaced.
    @Test(arguments: ["''", "'   '"])
    func aBlankNameUsesTheHostName(name: String) throws {
        let parsed = try config(
            """
            device:
              name: \(name)
            """
        )

        #expect(parsed.device.name == ZeitConfig.DeviceConfig.hostName)
    }

    /// A name that is not a string, and a `device:` block that is not a
    /// mapping: both read as "not set" rather than failing the load.
    @Test(arguments: ["device:\n  name: 42", "device: 'Work MBP'"])
    func aMalformedDeviceBlockUsesTheHostName(yaml: String) throws {
        #expect(try config(yaml).device.name == ZeitConfig.DeviceConfig.hostName)
    }

    @Test
    func theDefaultIsTheHostNameAndIsNeverEmpty() {
        #expect(!ZeitConfig.DeviceConfig.hostName.isEmpty)
        #expect(ZeitConfig.defaultDevice.name == ZeitConfig.DeviceConfig.hostName)
    }

    /// The config a fresh install writes shows the key but leaves it commented
    /// out, so the machine's own name keeps following a rename.
    @Test
    func theShippedConfigLeavesTheNameToTheHost() throws {
        #expect(try config(ZeitConfig.defaultConfigYAML).device.name
            == ZeitConfig.DeviceConfig.hostName)
        #expect(ZeitConfig.defaultConfigYAML.contains("# device:"))
    }

    @Test
    func aNameWithSurroundingWhitespaceIsTrimmed() throws {
        let parsed = try config(
            """
            device:
              name: '  Work MBP  '
            """
        )

        #expect(parsed.device.name == "Work MBP")
    }
}

/// The field on the entry: written by a capture, absent on everything stored
/// before it existed.
@Suite
struct ActivityEntryDeviceTests {
    private func entry(device: String?) -> ActivityEntry {
        ActivityEntry(
            timestamp: "2026-01-05T10:00:00Z",
            activity: .workCoding,
            reasoning: "An IDE with company code",
            description: "Editing a Swift file",
            device: device
        )
    }

    private func decode(_ json: String) throws -> [ActivityEntry] {
        try JSONDecoder().decode([ActivityEntry].self, from: Data(json.utf8))
    }

    @Test
    func aCaptureStampsTheConfiguredDevice() {
        #if DEBUG
        let result = IdentificationResult(
            activity: .workCoding,
            reasoning: "An IDE with company code",
            description: "Editing a Swift file",
            activeScreen: 1,
            screenshotPaths: nil,
            screenDebugInfo: nil,
            samplePath: nil
        )
        #else
        let result = IdentificationResult(
            activity: .workCoding,
            reasoning: "An IDE with company code",
            description: "Editing a Swift file",
            activeScreen: 1,
            screenshotPaths: nil,
            screenDebugInfo: nil
        )
        #endif

        let entry = result.toActivityEntry(device: "Work MBP")
        #expect(entry.device == "Work MBP")
        #expect(entry.activity == .workCoding)
    }

    @Test
    func theDeviceSurvivesARoundTrip() throws {
        let data = try JSONEncoder().encode([entry(device: "Work MBP")])
        let decoded = try JSONDecoder().decode([ActivityEntry].self, from: data)

        #expect(decoded.map(\.device) == ["Work MBP"])
    }

    /// An entry without a device writes no key, so a day of them is the same
    /// JSON Zeit wrote before the field existed.
    @Test
    func anEntryWithoutADeviceWritesNoKey() throws {
        let data = try JSONEncoder().encode([entry(device: nil)])
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains("device"))
    }

    @Test
    func aStoredEntryFromBeforeTheFieldDecodesWithoutOne() throws {
        let decoded = try decode(
            """
            [{"timestamp":"2026-01-05T10:00:00Z","activity":"work_coding",
              "reasoning":"An IDE","description":"Editing a Swift file"}]
            """
        )

        #expect(decoded.count == 1)
        #expect(decoded[0].device == nil)
        #expect(decoded[0].activity == .workCoding)
    }

    /// The day an install upgrades mid-day: old entries and new ones in one
    /// array, which still decodes and still breaks down.
    @Test
    func aDayMixingOldAndNewEntriesLoadsAndRenders() throws {
        let decoded = try decode(
            """
            [{"timestamp":"2026-01-05T10:00:00Z","activity":"work_coding",
              "description":"Editing a Swift file"},
             {"timestamp":"2026-01-05T10:01:00Z","activity":"work_coding",
              "description":"Editing a Swift file","device":"Work MBP"},
             {"timestamp":"2026-01-05T10:02:00Z","activity":"personal_browsing",
              "description":"Reading the news","device":"Work MBP"}]
            """
        )

        #expect(decoded.map(\.device) == [nil, "Work MBP", "Work MBP"])

        let stats = computeActivityBreakdown(from: decoded)
        #expect(stats.map(\.count) == [2, 1])
        #expect(abs(share(of: .work, in: stats) - 200.0 / 3.0) < 0.001)
        #expect(abs(share(of: .personal, in: stats) - 100.0 / 3.0) < 0.001)
        #expect(unclassifiedShare(in: stats) == 0.0)
    }
}

/// Storage: the field goes in and comes back out, and a row written before it
/// existed can still be appended to.
@Suite
struct DeviceStorageTests {
    private func database() throws -> (DatabaseHelper, DatabaseQueue) {
        let queue = try DatabaseQueue()
        try ZeitDatabase.prepare(queue)
        return (DatabaseHelper(queue: queue), queue)
    }

    private func entry(_ minute: Int, device: String?) -> ActivityEntry {
        ActivityEntry(
            timestamp: String(format: "2026-01-05T10:%02d:00Z", minute),
            activity: .workCoding,
            reasoning: nil,
            description: nil,
            device: device
        )
    }

    private func insert(_ entry: ActivityEntry, into db: DatabaseHelper) async throws {
        try await db.insertActivity(entry, attribution: .calendarDay, calendar: utcCalendar)
    }

    @Test
    func anEntryIsStoredAndReadBackWithItsDevice() async throws {
        let (db, _) = try database()

        try await insert(entry(0, device: "Work MBP"), into: db)

        let record = try await db.getDayRecord(date: "2026-01-05")
        #expect(record?.activities.map(\.device) == ["Work MBP"])
    }

    /// The upgrade path: a day already on disk with no devices, appended to by
    /// a tracking run that has one.
    @Test
    func aDayStoredBeforeTheFieldStillLoadsAndAccepts() async throws {
        let (db, queue) = try database()

        try await queue.write { raw in
            try raw.execute(
                sql: """
                    INSERT INTO daily_activities (date, activities, created_at, updated_at)
                    VALUES ('2026-01-05', ?, '2026-01-05T00:00:00Z', '2026-01-05T00:00:00Z')
                    """,
                arguments: [
                    """
                    [{"timestamp":"2026-01-05T09:00:00Z","activity":"work_coding",
                      "description":"Editing a Swift file"}]
                    """
                ]
            )
        }

        try await insert(entry(0, device: "Work MBP"), into: db)

        let record = try await db.getDayRecord(date: "2026-01-05")
        #expect(record?.count == 2)
        #expect(record?.activities.map(\.device) == [nil, "Work MBP"])

        let stats = computeActivityBreakdown(
            from: record?.activities ?? [], activityTypes: try await db.getActivityTypes()
        )
        #expect(share(of: .work, in: stats) == 100.0)
    }
}
