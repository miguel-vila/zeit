import ArgumentParser
import Foundation

/// CLI command to set activity types.
///
/// Each entry is "Name: Description" separated by semicolons.
/// When only --work or only --personal is provided, the other category
/// is preserved from the existing database.
struct SetActivityTypesCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "set-activity-types",
        abstract: "Set activity types for tracking"
    )

    @Option(name: .long, help: "Work activity types as semicolon-separated 'Name: Description' entries")
    var work: String?

    @Option(name: .long, help: "Personal activity types as semicolon-separated 'Name: Description' entries")
    var personal: String?

    func validate() throws {
        guard work != nil || personal != nil else {
            throw ValidationError("At least one of --work or --personal must be specified")
        }

        if let work = work {
            let parsed = try parseEntries(work, label: "work")
            try validateEntries(parsed, label: "work")
        }

        if let personal = personal {
            let parsed = try parseEntries(personal, label: "personal")
            try validateEntries(parsed, label: "personal")
        }

        // Cross-category checks
        if let work = work, let personal = personal {
            let workParsed = try parseEntries(work, label: "work")
            let personalParsed = try parseEntries(personal, label: "personal")

            let workNames = Set(workParsed.map { $0.name.lowercased() })
            let personalNames = Set(personalParsed.map { $0.name.lowercased() })
            let overlap = workNames.intersection(personalNames)
            if let dup = overlap.first {
                throw ValidationError("Activity name '\(dup)' appears in both --work and --personal")
            }

            let total = workParsed.count + personalParsed.count
            if total > ActivityTypeValidator.maxTotalTypes {
                throw ValidationError(
                    "Too many activity types (\(total)). Maximum is \(ActivityTypeValidator.maxTotalTypes)"
                )
            }
        }
    }

    func run() async throws {
        let db = try DatabaseHelper()
        let existingTypes = try await db.getActivityTypes()

        var workTypes: [ActivityType]
        var personalTypes: [ActivityType]

        if let workStr = work {
            workTypes = try parseEntries(workStr, label: "work").map {
                ActivityType(id: $0.id, name: $0.name, description: $0.description, isWork: true)
            }
        } else {
            // Preserve existing work types
            workTypes = existingTypes.filter(\.isWork)
        }

        if let personalStr = personal {
            personalTypes = try parseEntries(personalStr, label: "personal").map {
                ActivityType(id: $0.id, name: $0.name, description: $0.description, isWork: false)
            }
        } else {
            // Preserve existing personal types
            personalTypes = existingTypes.filter { !$0.isWork }
        }

        let allTypes = workTypes + personalTypes
        try await db.saveActivityTypes(allTypes)

        print("Activity types updated!")
        print("")
        print("WORK (\(workTypes.count)):")
        for type in workTypes {
            print("  \(type.id): \(type.description)")
        }
        print("")
        print("PERSONAL (\(personalTypes.count)):")
        for type in personalTypes {
            print("  \(type.id): \(type.description)")
        }
    }

    // MARK: - Parsing

    private struct ParsedEntry {
        let name: String
        let description: String
        let id: String
    }

    private func parseEntries(_ str: String, label: String) throws -> [ParsedEntry] {
        let entries = str.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [ParsedEntry] = []

        for entry in entries where !entry.isEmpty {
            guard entry.contains(":") else {
                throw ValidationError(
                    "Invalid format for entry '\(entry)'. Expected 'Name: Description'"
                )
            }

            let parts = entry.split(separator: ":", maxSplits: 1)
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let description = parts.count > 1
                ? parts[1].trimmingCharacters(in: .whitespaces)
                : ""

            guard !name.isEmpty else {
                throw ValidationError("Empty activity name found in --\(label) argument")
            }

            guard !description.isEmpty else {
                throw ValidationError("Empty description for activity '\(name)'")
            }

            let id = ActivityType.generateID(from: name)

            result.append(ParsedEntry(name: name, description: description, id: id))
        }

        return result
    }

    private func validateEntries(_ entries: [ParsedEntry], label: String) throws {
        var seenNames = Set<String>()
        for entry in entries {
            if entry.name.count > ActivityTypeValidator.maxNameLength {
                throw ValidationError("Activity name '\(entry.name)' exceeds \(ActivityTypeValidator.maxNameLength) characters")
            }
            if entry.description.count > ActivityTypeValidator.maxDescriptionLength {
                throw ValidationError("Description for '\(entry.name)' exceeds \(ActivityTypeValidator.maxDescriptionLength) characters")
            }
            let lower = entry.name.lowercased()
            if seenNames.contains(lower) {
                throw ValidationError("Duplicate \(label) activity name: '\(entry.name)'")
            }
            seenNames.insert(lower)

            if entry.id == "idle" {
                throw ValidationError("Activity name '\(entry.name)' conflicts with reserved system type 'idle'")
            }
        }
    }
}
