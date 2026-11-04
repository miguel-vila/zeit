import Foundation

/// One editable window row. Carries an identity the config shape does not need,
/// so a row keeps its place in the list while its days and times change.
struct ScheduleWindowDraft: Equatable, Identifiable, Sendable {
    let id: UUID
    var days: Set<ZeitConfig.Weekday>
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    init(
        id: UUID = UUID(),
        days: Set<ZeitConfig.Weekday>,
        startHour: Int, startMinute: Int,
        endHour: Int, endMinute: Int
    ) {
        self.id = id
        self.days = days
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    init(id: UUID = UUID(), window: ZeitConfig.ScheduleWindow) {
        self.init(
            id: id,
            days: window.days,
            startHour: window.startHour, startMinute: window.startMinute,
            endHour: window.endHour, endMinute: window.endMinute
        )
    }

    var window: ZeitConfig.ScheduleWindow {
        ZeitConfig.ScheduleWindow(
            days: days,
            startHour: startHour, startMinute: startMinute,
            endHour: endHour, endMinute: endMinute
        )
    }

    /// A new row starts as the default window, which is also what one window
    /// looked like before the schedule had more than one.
    static var `default`: ScheduleWindowDraft {
        ScheduleWindowDraft(window: ZeitConfig.defaultScheduleWindow)
    }
}

/// The schedule as the onboarding step and the Schedule settings tab edit it:
/// a form (Always or Windows) plus the window rows, and under them the cadence
/// and the battery gate.
///
/// The rows survive switching to Always and back, so the choice is not
/// destructive while the sheet is open.
struct ScheduleEditorState: Equatable, Sendable {
    var isAlways: Bool = false
    var windows: [ScheduleWindowDraft] = [.default]
    var intervalSeconds: Int = ZeitConfig.defaultTracking.intervalSeconds
    var skipOnBattery: Bool = ZeitConfig.defaultTracking.skipOnBattery

    init(
        schedule: ZeitConfig.ScheduleConfig = ZeitConfig.defaultSchedule,
        tracking: ZeitConfig.TrackingConfig = ZeitConfig.defaultTracking
    ) {
        load(schedule, tracking: tracking)
    }

    mutating func load(
        _ schedule: ZeitConfig.ScheduleConfig,
        tracking: ZeitConfig.TrackingConfig
    ) {
        intervalSeconds = Self.clamped(tracking.intervalSeconds)
        skipOnBattery = tracking.skipOnBattery

        switch schedule {
        case .always:
            isAlways = true
            windows = [.default]
        case .windows(let windows):
            isAlways = false
            // An empty list cannot be edited back into a valid schedule, so a
            // config that somehow holds one opens on the default row.
            self.windows = windows.isEmpty
                ? [.default]
                : windows.map { ScheduleWindowDraft(window: $0) }
        }
    }

    /// What `ZeitConfig.saveSchedule` is given.
    var schedule: ZeitConfig.ScheduleConfig {
        isAlways ? .always : .windows(windows.map(\.window))
    }

    /// The other half of what `ZeitConfig.saveSchedule` is given.
    var tracking: ZeitConfig.TrackingConfig {
        ZeitConfig.TrackingConfig(
            intervalSeconds: intervalSeconds,
            skipOnBattery: skipOnBattery
        )
    }

    /// What the cadence picker shows and selects. `intervalSeconds` is a plain
    /// Int so the picker can bind to it, so the clamp `TrackingConfig` applies
    /// has to be visible here too, or the picker would select a value the saved
    /// config does not hold.
    static func clamped(_ intervalSeconds: Int) -> Int {
        max(intervalSeconds, ZeitConfig.TrackingConfig.minimumIntervalSeconds)
    }

    /// The cadences the editor offers, plus whatever the config already holds:
    /// a hand-edited interval has to be visible to be changed.
    var intervalOptions: [Int] {
        Set(Self.intervalPresets + [Self.clamped(intervalSeconds)]).sorted()
    }

    static let intervalPresets = [60, 120, 300, 600, 900, 1800]

    /// "5 min" for a round cadence, "90s" for a hand-edited one.
    static func intervalLabel(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds)s"
    }

    mutating func addWindow() {
        windows.append(.default)
    }

    /// Removing the last row would mean "never track", so the list keeps one.
    mutating func removeWindow(id: UUID) {
        guard windows.count > 1 else { return }
        windows.removeAll { $0.id == id }
    }

    /// Apply an edited row. A window with no days is not a window, so an empty
    /// day set keeps the days the row had.
    mutating func update(_ window: ScheduleWindowDraft) {
        guard let index = windows.firstIndex(where: { $0.id == window.id }) else { return }
        var window = window
        if window.days.isEmpty {
            window.days = windows[index].days
        }
        windows[index] = window
    }
}
