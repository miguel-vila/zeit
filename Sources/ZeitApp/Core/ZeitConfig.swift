import Foundation
import Yams

/// Shared configuration loaded from ~/.local/share/zeit/conf.yml
struct ZeitConfig: Sendable {
    let workHours: WorkHoursConfig
    let models: ModelsConfig

    struct WorkHoursConfig: Sendable {
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int
        let workDays: Set<Weekday>
    }

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

    struct ModelsConfig: Sendable {
        let vision: String
        let text: TextModelConfig

        struct TextModelConfig: Sendable {
            let provider: String
            let model: String
        }
    }

    // MARK: - Defaults

    static let defaultWorkDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    static let defaultWorkHours = WorkHoursConfig(
        startHour: 9, startMinute: 0,
        endHour: 17, endMinute: 30,
        workDays: defaultWorkDays
    )

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

    private static let defaultConfigYAML = """
        work_hours:
          start_hour: 9
          start_minute: 0
          end_hour: 17
          end_minute: 30
          work_days: ['mon', 'tue', 'wed', 'thu', 'fri']

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
            return ZeitConfig(workHours: defaultWorkHours, models: defaultModels)
        }

        let workHours = parseWorkHours(from: yaml)
        let models = parseModels(from: yaml)

        return ZeitConfig(workHours: workHours, models: models)
    }

    // MARK: - Parsing

    private static func parseWorkHours(from yaml: [String: Any]) -> WorkHoursConfig {
        guard let workHours = yaml["work_hours"] as? [String: Any] else {
            return defaultWorkHours
        }

        // Support both integer "start_hour" and string "work_start_hour: '09:00'" formats
        let startHour: Int
        let startMinute: Int
        if let hour = workHours["start_hour"] as? Int {
            startHour = hour
            startMinute = workHours["start_minute"] as? Int ?? defaultWorkHours.startMinute
        } else if let hourStr = workHours["work_start_hour"] as? String,
                  let parsed = parseTimeString(hourStr) {
            startHour = parsed.hour
            startMinute = parsed.minute
        } else {
            startHour = defaultWorkHours.startHour
            startMinute = defaultWorkHours.startMinute
        }

        let endHour: Int
        let endMinute: Int
        if let hour = workHours["end_hour"] as? Int {
            endHour = hour
            endMinute = workHours["end_minute"] as? Int ?? defaultWorkHours.endMinute
        } else if let hourStr = workHours["work_end_hour"] as? String,
                  let parsed = parseTimeString(hourStr) {
            endHour = parsed.hour
            endMinute = parsed.minute
        } else {
            endHour = defaultWorkHours.endHour
            endMinute = defaultWorkHours.endMinute
        }

        let workDays = parseWorkDays(from: workHours)

        return WorkHoursConfig(
            startHour: startHour, startMinute: startMinute,
            endHour: endHour, endMinute: endMinute,
            workDays: workDays
        )
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

    /// Parse work days from the work_hours YAML section
    private static func parseWorkDays(from workHours: [String: Any]) -> Set<Weekday> {
        guard let daysList = workHours["work_days"] as? [Any] else {
            return defaultWorkDays
        }

        var days = Set<Weekday>()
        for day in daysList {
            if let dayStr = day as? String, let weekday = weekdayFromString(dayStr) {
                days.insert(weekday)
            } else if let dayInt = day as? Int, let weekday = Weekday(rawValue: dayInt) {
                days.insert(weekday)
            }
        }

        return days.isEmpty ? defaultWorkDays : days
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

    /// Update work hours in the config file, preserving all other settings.
    static func saveWorkHours(
        startHour: Int, startMinute: Int,
        endHour: Int, endMinute: Int,
        workDays: Set<Weekday>
    ) throws {
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

        // Sort days by rawValue for consistent output
        let sortedDays = workDays.sorted().map { $0.shortName.lowercased() }

        // Update work_hours section
        yaml["work_hours"] = [
            "start_hour": startHour,
            "start_minute": startMinute,
            "end_hour": endHour,
            "end_minute": endMinute,
            "work_days": sortedDays,
        ]

        let output = try Yams.dump(object: yaml)
        try output.write(to: path, atomically: true, encoding: .utf8)
    }
}
