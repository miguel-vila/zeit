import Foundation

/// The tracker's log, as someone reads it back later.
///
/// `zeit track` runs under launchd, which captures stdout to
/// `~/Library/Logs/zeit/tracker.out.log` and adds nothing of its own. A bare
/// `print` therefore leaves a line that cannot be placed in time, and a log of
/// such lines cannot answer the two questions it is kept for: when a tick ran,
/// and how long it took. Both are the gap between two stamped lines.
///
/// Every line carries its moment, including each line of a multi-line message,
/// so no line in the log is unplaceable. The format lives here alone so the log
/// cannot be stamped two ways.
enum TrackerLog {
    /// Local time to the second, as an internet date: a log read next to a
    /// person's own day, sortable, and unambiguous about the offset.
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()

    /// The stamped form of `message`, which is what the log holds.
    ///
    /// Separated from `write` so the format can be exercised without capturing
    /// standard output.
    static func line(_ message: String, at moment: Date = Date()) -> String {
        let stamp = formatter.string(from: moment)
        return message
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\(stamp)  \($0)" }
            .joined(separator: "\n")
    }

    static func write(_ message: String, at moment: Date = Date()) {
        print(line(message, at: moment))
    }
}
