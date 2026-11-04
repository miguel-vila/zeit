import Foundation
import Yams
import os

private let logger = Logger(subsystem: "com.zeit", category: "ZeitConfig")

/// Shared configuration loaded from ~/.local/share/zeit/conf.yml
struct ZeitConfig: Sendable {
    let schedule: ScheduleConfig
    let tracking: TrackingConfig
    let models: ModelsConfig
    let classification: ClassificationConfig

    /// Days of the week, matching Calendar.component(.weekday) values.
    /// Sunday=1, Monday=2, ..., Saturday=7
    enum Weekday: Int, Sendable, CaseIterable, Comparable, Codable {
        case sunday = 1
        case monday = 2
        case tuesday = 3
        case wednesday = 4
        case thursday = 5
        case friday = 6
        case saturday = 7

        var shortName: String {
            switch self {
            case .sunday: return "Sun"
            case .monday: return "Mon"
            case .tuesday: return "Tue"
            case .wednesday: return "Wed"
            case .thursday: return "Thu"
            case .friday: return "Fri"
            case .saturday: return "Sat"
            }
        }

        var fullName: String {
            switch self {
            case .sunday: return "Sunday"
            case .monday: return "Monday"
            case .tuesday: return "Tuesday"
            case .wednesday: return "Wednesday"
            case .thursday: return "Thursday"
            case .friday: return "Friday"
            case .saturday: return "Saturday"
            }
        }

        static func < (lhs: Weekday, rhs: Weekday) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// How often this machine tracks, and when it holds off.
    ///
    /// The schedule lives in the same `tracking:` block but stays its own
    /// field: it answers "does this machine track at all now?", which the
    /// menubar and the CLI ask on their own, while these answer "is *this
    /// tick* due?".
    struct TrackingConfig: Sendable, Equatable {
        /// Seconds between tracked entries. launchd keeps firing every 60
        /// seconds; a tracking run compares this against the newest stored
        /// entry and decides whether the tick is due.
        let intervalSeconds: Int

        /// Whether to skip a tick while the machine runs on battery.
        let skipOnBattery: Bool

        /// The launchd tick, and so the shortest cadence that can be honoured.
        static let minimumIntervalSeconds = 60

        /// A shorter interval than the tick is raised here, so no caller — the
        /// config reader, the editor, the writer — can hold a cadence that
        /// cannot be honoured.
        init(intervalSeconds: Int, skipOnBattery: Bool) {
            self.intervalSeconds = max(intervalSeconds, Self.minimumIntervalSeconds)
            self.skipOnBattery = skipOnBattery
        }
    }

    /// How this machine groups the time it tracks.
    struct ClassificationConfig: Sendable {
        /// The group this machine is judged by: the share the menubar icon shows.
        ///
        /// A machine does not declare which groups it uses — it has a group when
        /// it has types in that group — so this is the only classification
        /// setting that is stored.
        let primaryGroup: ActivityGroup
    }

    struct ModelsConfig: Sendable {
        let vision: String
        let text: TextModelConfig

        struct TextModelConfig: Sendable {
            let provider: String
            let model: String
        }
    }

    // MARK: - Defaults

    static let defaultScheduleDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    static let defaultScheduleWindow = ScheduleWindow(
        days: defaultScheduleDays,
        startHour: 9, startMinute: 0,
        endHour: 17, endMinute: 30
    )

    static let defaultSchedule = ScheduleConfig.windows([defaultScheduleWindow])

    static let defaultTracking = TrackingConfig(
        intervalSeconds: TrackingConfig.minimumIntervalSeconds,
        skipOnBattery: false
    )

    static let defaultClassification = ClassificationConfig(primaryGroup: .work)

    static let defaultModels = ModelsConfig(
        vision: "qwen3-vl:4b",
        text: .init(provider: "mlx", model: "qwen3:8b")
    )

    // MARK: - Paths

    static let dataDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/zeit")

    static var configPath: URL {
        dataDir.appendingPathComponent("conf.yml")
    }

    // MARK: - Default Config Content

    /// What `ensureSetup()` writes when there is no config file yet.
    static let defaultConfigYAML = """
        tracking:
          schedule:              # 'always', or a list of windows
            windows:
              - days: ['mon', 'tue', 'wed', 'thu', 'fri']
                from: '09:00'
                to: '17:30'
          interval_seconds: 60   # seconds between entries, minimum 60
          skip_on_battery: false # hold off while running on battery

        classification:
          primary_group: 'work'   # 'work', 'personal_projects' or 'personal'

        models:
          vision: 'qwen3-vl:4b'
          text:
            provider: 'mlx'     # 'mlx' (on-device) or 'openai'
            model: 'qwen3:8b'   # e.g., 'gpt-4o-mini' for openai

        paths:
          data_dir: '~/.local/share/zeit'
          stop_flag: '~/.local/share/zeit/.zeit_stop'
          db_path: '~/.local/share/zeit/zeit.db'
        """

    // MARK: - Bootstrap

    /// Ensure the data directory and default config file exist.
    /// Call this early in app startup (both CLI and GUI paths).
    static func ensureSetup() {
        let fm = FileManager.default

        // Create data directory if needed
        if !fm.fileExists(atPath: dataDir.path) {
            try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        }

        // Write default config if no config file exists
        let configFile = configPath
        if !fm.fileExists(atPath: configFile.path) {
            try? defaultConfigYAML.write(to: configFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Loading

    /// Load configuration from conf.yml, falling back to defaults for missing values.
    static func load() -> ZeitConfig {
        ensureSetup()

        let path = configPath

        guard FileManager.default.fileExists(atPath: path.path),
              let contents = try? String(contentsOf: path, encoding: .utf8),
              let yaml = try? Yams.load(yaml: contents) as? [String: Any]
        else {
            return ZeitConfig(
                schedule: defaultSchedule,
                tracking: defaultTracking,
                models: defaultModels,
                classification: defaultClassification
            )
        }

        return parse(yaml: yaml)
    }

    /// Build a config from an already-parsed YAML mapping, falling back to the
    /// defaults for anything missing.
    ///
    /// Separated from `load()` so parsing can be exercised without a config file
    /// on disk.
    static func parse(yaml: [String: Any]) -> ZeitConfig {
        ZeitConfig(
            schedule: parseSchedule(from: yaml),
            tracking: parseTracking(from: yaml),
            models: parseModels(from: yaml),
            classification: parseClassification(from: yaml)
        )
    }

    // MARK: - Parsing

    /// `tracking.schedule` is either the string `always` or a mapping with a
    /// non-empty `windows` list. Anything else — including `windows: []` — keeps
    /// the last valid value Zeit has, which for a stateless load is the shipped
    /// default, and logs the fallback: a silent "never track" is worse than a
    /// loud one.
    static func parseSchedule(from yaml: [String: Any]) -> ScheduleConfig {
        guard let tracking = yaml["tracking"] as? [String: Any],
              let schedule = tracking["schedule"]
        else {
            return parseLegacyWorkHours(from: yaml) ?? defaultSchedule
        }

        if let form = schedule as? String {
            guard form.trimmingCharacters(in: .whitespaces).lowercased() == "always" else {
                logger.warning(
                    "tracking.schedule: '\(form, privacy: .public)' is not a schedule, keeping \(defaultSchedule.summary, privacy: .public)"
                )
                return defaultSchedule
            }
            return .always
        }

        guard let mapping = schedule as? [String: Any],
              let list = mapping["windows"] as? [Any]
        else {
            logger.warning(
                "tracking.schedule: expected 'always' or a 'windows' list, keeping \(defaultSchedule.summary, privacy: .public)"
            )
            return defaultSchedule
        }

        let windows = list.compactMap { entry -> ScheduleWindow? in
            guard let window = entry as? [String: Any] else { return nil }
            return parseScheduleWindow(from: window)
        }

        guard !windows.isEmpty else {
            logger.warning(
                "tracking.schedule.windows: no usable window, keeping \(defaultSchedule.summary, privacy: .public)"
            )
            return defaultSchedule
        }

        return .windows(windows)
    }

    /// One `windows:` entry: `days`, `from` and `to`. A window missing any of
    /// the three is dropped rather than half-guessed.
    private static func parseScheduleWindow(from window: [String: Any]) -> ScheduleWindow? {
        let days = parseDays(window["days"])
        guard !days.isEmpty,
              let from = window["from"] as? String, let start = parseTimeString(from),
              let to = window["to"] as? String, let end = parseTimeString(to)
        else {
            return nil
        }

        return ScheduleWindow(
            days: days,
            startHour: start.hour, startMinute: start.minute,
            endHour: end.hour, endMinute: end.minute
        )
    }

    /// A pre-schedule config: the `work_hours:` block reads as a single window
    /// with its work days. Never written back.
    private static func parseLegacyWorkHours(from yaml: [String: Any]) -> ScheduleConfig? {
        guard let workHours = yaml["work_hours"] as? [String: Any] else {
            return nil
        }

        let fallback = defaultScheduleWindow

        // Support both integer "start_hour" and string "work_start_hour: '09:00'" formats
        let startHour: Int
        let startMinute: Int
        if let hour = workHours["start_hour"] as? Int {
            startHour = hour
            startMinute = workHours["start_minute"] as? Int ?? fallback.startMinute
        } else if let hourStr = workHours["work_start_hour"] as? String,
                  let parsed = parseTimeString(hourStr) {
            startHour = parsed.hour
            startMinute = parsed.minute
        } else {
            startHour = fallback.startHour
            startMinute = fallback.startMinute
        }

        let endHour: Int
        let endMinute: Int
        if let hour = workHours["end_hour"] as? Int {
            endHour = hour
            endMinute = workHours["end_minute"] as? Int ?? fallback.endMinute
        } else if let hourStr = workHours["work_end_hour"] as? String,
                  let parsed = parseTimeString(hourStr) {
            endHour = parsed.hour
            endMinute = parsed.minute
        } else {
            endHour = fallback.endHour
            endMinute = fallback.endMinute
        }

        let days = parseDays(workHours["work_days"])

        return .windows([
            ScheduleWindow(
                days: days.isEmpty ? defaultScheduleDays : days,
                startHour: startHour, startMinute: startMinute,
                endHour: endHour, endMinute: endMinute
            )
        ])
    }

    /// `tracking.interval_seconds` and `tracking.skip_on_battery`. An interval
    /// below the launchd tick is raised by `TrackingConfig` itself; the warning
    /// is here so a cadence that cannot be honoured is not raised silently.
    static func parseTracking(from yaml: [String: Any]) -> TrackingConfig {
        guard let tracking = yaml["tracking"] as? [String: Any] else {
            return defaultTracking
        }

        let configured = tracking["interval_seconds"] as? Int
        let parsed = TrackingConfig(
            intervalSeconds: configured ?? defaultTracking.intervalSeconds,
            skipOnBattery: tracking["skip_on_battery"] as? Bool ?? defaultTracking.skipOnBattery
        )

        if let configured, configured != parsed.intervalSeconds {
            logger.warning(
                """
                tracking.interval_seconds: \(configured, privacy: .public)s is below the \
                \(TrackingConfig.minimumIntervalSeconds, privacy: .public)s tick, \
                using \(parsed.intervalSeconds, privacy: .public)s
                """
            )
        }

        return parsed
    }

    /// A missing or unrecognised `primary_group` falls back to the default
    /// instead of failing the load: the rest of the config is still usable.
    private static func parseClassification(from yaml: [String: Any]) -> ClassificationConfig {
        guard let classification = yaml["classification"] as? [String: Any],
              let raw = classification["primary_group"] as? String,
              let group = ActivityGroup(rawValue: raw.lowercased())
        else {
            return defaultClassification
        }

        return ClassificationConfig(primaryGroup: group)
    }

    private static func parseModels(from yaml: [String: Any]) -> ModelsConfig {
        guard let models = yaml["models"] as? [String: Any] else {
            return defaultModels
        }

        let vision = models["vision"] as? String ?? defaultModels.vision

        let textConfig: ModelsConfig.TextModelConfig
        if let text = models["text"] as? [String: Any] {
            let provider = text["provider"] as? String ?? defaultModels.text.provider
            let model = text["model"] as? String ?? defaultModels.text.model
            textConfig = .init(provider: provider, model: model)
        } else {
            textConfig = defaultModels.text
        }

        return ModelsConfig(vision: vision, text: textConfig)
    }

    /// Parse hour and minute from "HH:MM" format string
    private static func parseTimeString(_ timeStr: String) -> (hour: Int, minute: Int)? {
        let parts = timeStr.split(separator: ":")
        guard let hourStr = parts.first, let hour = Int(hourStr) else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return (hour, minute)
    }

    /// Parse a YAML day list, which may name days (`'mon'`) or number them.
    /// Unknown entries are dropped; the caller decides what an empty set means.
    private static func parseDays(_ value: Any?) -> Set<Weekday> {
        guard let daysList = value as? [Any] else {
            return []
        }

        var days = Set<Weekday>()
        for day in daysList {
            if let dayStr = day as? String, let weekday = weekdayFromString(dayStr) {
                days.insert(weekday)
            } else if let dayInt = day as? Int, let weekday = Weekday(rawValue: dayInt) {
                days.insert(weekday)
            }
        }

        return days
    }

    /// Convert short day name to Weekday
    private static func weekdayFromString(_ str: String) -> Weekday? {
        switch str.lowercased() {
        case "sun", "sunday": return .sunday
        case "mon", "monday": return .monday
        case "tue", "tuesday": return .tuesday
        case "wed", "wednesday": return .wednesday
        case "thu", "thursday": return .thursday
        case "fri", "friday": return .friday
        case "sat", "saturday": return .saturday
        default: return nil
        }
    }

    // MARK: - Saving

    /// Update model selection in the config file, preserving all other settings.
    static func saveModels(
        vision: String,
        textProvider: String,
        textModel: String
    ) throws {
        ensureSetup()

        let path = configPath

        var yaml: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: path.path),
           let contents = try? String(contentsOf: path, encoding: .utf8),
           let parsed = try? Yams.load(yaml: contents) as? [String: Any]
        {
            yaml = parsed
        }

        yaml["models"] = [
            "vision": vision,
            "text": [
                "provider": textProvider,
                "model": textModel,
            ],
        ]

        let output = try Yams.dump(object: yaml)
        try output.write(to: path, atomically: true, encoding: .utf8)
    }

    /// Update the primary group in the config file, preserving all other settings.
    static func savePrimaryGroup(_ group: ActivityGroup) throws {
        ensureSetup()

        let path = configPath

        var yaml: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: path.path),
           let contents = try? String(contentsOf: path, encoding: .utf8),
           let parsed = try? Yams.load(yaml: contents) as? [String: Any]
        {
            yaml = parsed
        }

        var classification = yaml["classification"] as? [String: Any] ?? [:]
        classification["primary_group"] = group.rawValue
        yaml["classification"] = classification

        let output = try Yams.dump(object: yaml)
        try output.write(to: path, atomically: true, encoding: .utf8)
    }

    /// Update the tracking schedule in the config file, preserving all other
    /// settings.
    ///
    /// `tracking` is written only when given: `zeit schedule` changes the
    /// windows without touching the cadence, while the editor saves both in
    /// one pass.
    static func saveSchedule(_ schedule: ScheduleConfig, tracking: TrackingConfig? = nil) throws {
        ensureSetup()

        let path = configPath

        // Load existing YAML as a dictionary so we preserve other keys
        var yaml: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: path.path),
           let contents = try? String(contentsOf: path, encoding: .utf8),
           let parsed = try? Yams.load(yaml: contents) as? [String: Any]
        {
            yaml = parsed
        }

        let output = try Yams.dump(object: applying(schedule, tracking: tracking, to: yaml))
        try output.write(to: path, atomically: true, encoding: .utf8)
    }

    /// Write the schedule into an already-parsed YAML mapping.
    ///
    /// Only the new shape is written, and a legacy `work_hours:` block is
    /// dropped so the two cannot disagree afterwards. Separated from
    /// `saveSchedule` so the written shape can be exercised without a config
    /// file on disk.
    static func applying(
        _ schedule: ScheduleConfig,
        tracking cadence: TrackingConfig? = nil,
        to yaml: [String: Any]
    ) -> [String: Any] {
        var yaml = yaml
        yaml.removeValue(forKey: "work_hours")

        var tracking = yaml["tracking"] as? [String: Any] ?? [:]

        switch schedule {
        case .always:
            tracking["schedule"] = "always"
        case .windows(let windows):
            tracking["schedule"] = [
                "windows": windows.map { window in
                    [
                        // Sort days by rawValue for consistent output
                        "days": window.days.sorted().map { $0.shortName.lowercased() },
                        "from": String(format: "%02d:%02d", window.startHour, window.startMinute),
                        "to": String(format: "%02d:%02d", window.endHour, window.endMinute),
                    ] as [String: Any]
                }
            ]
        }

        if let cadence {
            tracking["interval_seconds"] = cadence.intervalSeconds
            tracking["skip_on_battery"] = cadence.skipOnBattery
        }

        yaml["tracking"] = tracking
        return yaml
    }
}
