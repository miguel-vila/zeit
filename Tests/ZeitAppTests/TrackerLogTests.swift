import Foundation
import Testing

@testable import ZeitApp

/// launchd adds nothing to what the tracker prints, so the log is only as
/// readable as the lines themselves. Every line must say when it happened,
/// because a tick's duration is the gap between two of them.
@Suite
struct TrackerLogTests {
    private let moment = Date(timeIntervalSince1970: 1_767_610_800)

    @Test
    func aLineCarriesItsMoment() {
        let line = TrackerLog.line("Capturing screenshots...", at: moment)

        #expect(line.hasSuffix("  Capturing screenshots..."))
        #expect(line.contains("2026-01-05T"))
    }

    /// A multi-line message would otherwise leave every line but the first
    /// unplaceable in time.
    @Test
    func everyLineOfAMessageCarriesTheMoment() {
        let line = TrackerLog.line("Screen 1: a\nScreen 2: b", at: moment)
        let lines = line.split(separator: "\n")

        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.contains("2026-01-05T") })
        #expect(lines.last?.hasSuffix("  Screen 2: b") == true)
    }

    /// The stamp is sortable and states its offset, so a log read in one place
    /// still resolves to a single moment.
    @Test
    func theStampIsAnInternetDateWithAnOffset() throws {
        let stamp = String(
            TrackerLog.line("x", at: moment).dropLast("  x".count)
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let parsed = try #require(formatter.date(from: stamp))

        #expect(parsed == moment)
    }
}
