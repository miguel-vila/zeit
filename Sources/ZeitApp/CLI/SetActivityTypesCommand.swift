import ArgumentParser
import Foundation

/// CLI command to set activity types for one or more groups.
///
/// `--group` and `--types` are repeatable and paired by position. Each `--types`
/// value is a semicolon-separated list of "Name: Description" entries. A group
/// named on the command line is replaced; a group not named is preserved.
struct SetActivityTypesCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "set-activity-types",
        abstract: "Set activity types for tracking",
        discussion: """
            Groups: \(ActivityGroup.allCases.map(\.rawValue).joined(separator: ", ")).

            Each --group must be followed by a --types value:

              zeit set-activity-types \\
                --group work --types "Coding: Code in company repos" \\
                --group personal --types "Social Media: X, Reddit"

            Groups that are not named keep the types they have.
            """
    )

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Group to replace. Repeatable; pair each with a --types value"
    )
    var group: [ActivityGroup] = []

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Activity types for the preceding --group as semicolon-separated 'Name: Description' entries"
    )
    var types: [String] = []

    func validate() throws {
        guard !group.isEmpty else {
            throw ValidationError("At least one --group with a --types value must be specified")
        }

        guard group.count == types.count else {
            throw ValidationError(
                "Each --group needs one --types value (got \(group.count) --group and \(types.count) --types)"
            )
        }

        var seenGroups = Set<ActivityGroup>()
        for named in group {
            if seenGroups.contains(named) {
                throw ValidationError("Group '\(named.rawValue)' is named more than once")
            }
            seenGroups.insert(named)
        }

        // Parse eagerly so a malformed entry fails before any write.
        _ = try parseReplacements()
    }

    func run() async throws {
        let db = try DatabaseHelper()
        let existingTypes = try await db.getActivityTypes()
        let allTypes = Self.merge(try parseReplacements(), into: existingTypes)

        if let error = allTypes.compactMap(ActivityTypeValidator.validateField).first {
            throw ValidationError(error.localizedDescription)
        }
        if let error = ActivityTypeValidator.validateAll(allTypes).first {
            throw ValidationError(error.localizedDescription)
        }

        try await db.saveActivityTypes(allTypes)

        print("Activity types updated!")
        for group in ActivityGroup.allCases {
            let groupTypes = allTypes.filter { $0.group == group }
            print("")
            print("\(group.displayName.uppercased()) (\(groupTypes.count)):")
            if groupTypes.isEmpty {
                print("  (none)")
            }
            for type in groupTypes {
                print("  \(type.id): \(type.description)")
            }
        }
    }

    // MARK: - Merging

    /// Replace the named groups and keep every group that was not named.
    static func merge(
        _ replacements: [ActivityGroup: [ActivityType]],
        into existing: [ActivityType]
    ) -> [ActivityType] {
        ActivityGroup.allCases.flatMap { group in
            replacements[group] ?? existing.filter { $0.group == group }
        }
    }

    // MARK: - Parsing

    /// The types supplied on the command line, keyed by the group they replace.
    private func parseReplacements() throws -> [ActivityGroup: [ActivityType]] {
        var replacements: [ActivityGroup: [ActivityType]] = [:]

        for (named, spec) in zip(group, types) {
            replacements[named] = try Self.parseEntries(spec, group: named)
        }

        return replacements
    }

    static func parseEntries(_ str: String, group: ActivityGroup) throws -> [ActivityType] {
        let entries = str.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [ActivityType] = []
        var seenNames = Set<String>()

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
                throw ValidationError("Empty activity name found in --group \(group.rawValue)")
            }

            guard !description.isEmpty else {
                throw ValidationError("Empty description for activity '\(name)'")
            }

            let lower = name.lowercased()
            if seenNames.contains(lower) {
                throw ValidationError(
                    "Duplicate activity name in --group \(group.rawValue): '\(name)'"
                )
            }
            seenNames.insert(lower)

            result.append(
                ActivityType(
                    id: ActivityType.generateID(from: name),
                    name: name,
                    description: description,
                    group: group
                )
            )
        }

        return result
    }
}
