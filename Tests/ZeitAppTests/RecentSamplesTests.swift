import Foundation
import Testing

@testable import ZeitApp

/// The window `zeit doctor` reports: what the tracker stored, how far apart,
/// and whether the catalog still defines the types named.
@Suite
struct RecentSamplesTests {
    private let start = Date(timeIntervalSince1970: 1_767_610_800)

    private func entry(
        _ offsetSeconds: TimeInterval,
        _ activity: Activity = .workCoding,
        device: String? = "Work MBP"
    ) -> ActivityEntry {
        ActivityEntry(
            timestamp: ISO8601DateFormatter().string(
                from: start.addingTimeInterval(offsetSeconds)
            ),
            activity: activity,
            reasoning: nil,
            description: nil,
            device: device
        )
    }

    private let catalog: Set<String> = ["work_coding", "social_media"]

    @Test
    func samplesComeBackNewestFirst() {
        let samples = RecentSamples.from(
            entries: [entry(0), entry(120), entry(60)],
            knownTypeIDs: catalog,
            limit: 20
        )

        #expect(samples.map(\.timestamp) == [
            start.addingTimeInterval(120),
            start.addingTimeInterval(60),
            start,
        ])
    }

    /// The gap is measured against the entry before it in time, whatever order
    /// the entries arrived in.
    @Test
    func eachSampleReportsTheGapBeforeIt() {
        let samples = RecentSamples.from(
            entries: [entry(0), entry(60), entry(180)],
            knownTypeIDs: catalog,
            limit: 20
        )

        #expect(samples.map(\.sincePrevious) == [120, 60, nil])
    }

    /// The window is cut after the gaps are measured, so the oldest sample
    /// shown still reports the gap that produced it.
    @Test
    func theOldestSampleInACutWindowKeepsItsGap() {
        let samples = RecentSamples.from(
            entries: [entry(0), entry(60), entry(120)],
            knownTypeIDs: catalog,
            limit: 2
        )

        #expect(samples.count == 2)
        #expect(samples.map(\.sincePrevious) == [60, 60])
    }

    @Test
    func aTypeMissingFromTheCatalogIsFlagged() {
        let samples = RecentSamples.from(
            entries: [entry(0, Activity(rawValue: "project_coding"))],
            knownTypeIDs: catalog,
            limit: 20
        )

        #expect(samples.map(\.isKnownType) == [false])
    }

    /// `idle` is written by the tracker, not chosen from the catalog, so it is
    /// never reported as a type the catalog has lost.
    @Test
    func idleIsAlwaysAKnownType() {
        let samples = RecentSamples.from(
            entries: [entry(0, .idle)],
            knownTypeIDs: [],
            limit: 20
        )

        #expect(samples.map(\.isKnownType) == [true])
    }

    /// An entry whose timestamp cannot be parsed has no place on a timeline,
    /// so it is dropped rather than given a guessed moment.
    @Test
    func anUnparseableTimestampIsDropped() {
        let broken = ActivityEntry(
            timestamp: "not a date",
            activity: .workCoding,
            reasoning: nil,
            description: nil,
            device: nil
        )

        let samples = RecentSamples.from(
            entries: [broken, entry(0)],
            knownTypeIDs: catalog,
            limit: 20
        )

        #expect(samples.count == 1)
        #expect(samples.first?.timestamp == start)
    }

    @Test
    func anEmptyWindowHasNoSamplesAndNoMedian() {
        let samples = RecentSamples.from(entries: [], knownTypeIDs: catalog, limit: 20)

        #expect(samples.isEmpty)
        #expect(RecentSamples.medianGap(of: samples) == nil)
    }

    /// A machine asleep for an hour leaves one enormous gap; the median keeps
    /// reporting the cadence the rest of the window ran at.
    @Test
    func theMedianGapIgnoresAnOutlier() {
        let samples = RecentSamples.from(
            entries: [entry(0), entry(60), entry(120), entry(3600)],
            knownTypeIDs: catalog,
            limit: 20
        )

        #expect(RecentSamples.medianGap(of: samples) == 60)
    }

    @Test
    func aSingleSampleHasNoMedianGap() {
        let samples = RecentSamples.from(entries: [entry(0)], knownTypeIDs: catalog, limit: 20)

        #expect(RecentSamples.medianGap(of: samples) == nil)
    }

    @Test
    func theDeviceTravelsWithTheSample() {
        let samples = RecentSamples.from(
            entries: [entry(0, device: nil), entry(60, device: "Work MBP")],
            knownTypeIDs: catalog,
            limit: 20
        )

        #expect(samples.map(\.device) == ["Work MBP", nil])
    }
}
