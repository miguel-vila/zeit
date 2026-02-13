import Foundation
import Yams

/// Shared configuration loaded from ~/.local/share/zeit/conf.yml
struct ZeitConfig: Sendable {
    let workHours: WorkHoursConfig
    let models: ModelsConfig

    struct WorkHoursConfig: Sendable {
        let startHour: Int
        let endHour: Int
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

    static let defaultWorkHours = WorkHoursConfig(startHour: 9, endHour: 18)

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
          end_hour: 18

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
        if let hour = workHours["start_hour"] as? Int {
            startHour = hour
        } else if let hourStr = workHours["work_start_hour"] as? String,
                  let hour = parseHourFromTimeString(hourStr) {
            startHour = hour
        } else {
            startHour = defaultWorkHours.startHour
        }

        let endHour: Int
        if let hour = workHours["end_hour"] as? Int {
            endHour = hour
        } else if let hourStr = workHours["work_end_hour"] as? String,
                  let hour = parseHourFromTimeString(hourStr) {
            endHour = hour
        } else {
            endHour = defaultWorkHours.endHour
        }

        return WorkHoursConfig(startHour: startHour, endHour: endHour)
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

    /// Parse hour from "HH:MM" format string
    private static func parseHourFromTimeString(_ timeStr: String) -> Int? {
        let parts = timeStr.split(separator: ":")
        guard let hourStr = parts.first, let hour = Int(hourStr) else { return nil }
        return hour
    }

    // MARK: - Saving

    /// Update work hours in the config file, preserving all other settings.
    static func saveWorkHours(startHour: Int, endHour: Int) throws {
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

        // Update work_hours section
        yaml["work_hours"] = [
            "start_hour": startHour,
            "end_hour": endHour,
        ]

        let output = try Yams.dump(object: yaml)
        try output.write(to: path, atomically: true, encoding: .utf8)
    }
}
