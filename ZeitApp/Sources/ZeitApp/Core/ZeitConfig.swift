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
        text: .init(provider: "ollama", model: "qwen3:8b")
    )

    // MARK: - Loading

    private static let dataDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/zeit")

    static var configPath: URL {
        dataDir.appendingPathComponent("conf.yml")
    }

    /// Load configuration from conf.yml, falling back to defaults for missing values.
    static func load() -> ZeitConfig {
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
}
