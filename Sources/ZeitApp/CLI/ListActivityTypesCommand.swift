import ArgumentParser
import Foundation

/// CLI command to list configured activity types.
struct ListActivityTypesCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "list-activity-types",
        abstract: "List configured activity types, grouped"
    )

    func run() async throws {
        let db = try DatabaseHelper()
        let types = try await db.getActivityTypes()
        let primaryGroup = ZeitConfig.load().classification.primaryGroup

        print("Activity Types")
        print("=" .repeated(50))

        for group in ActivityGroup.allCases {
            let groupTypes = types.filter { $0.group == group }
            let marker = group == primaryGroup ? " [primary]" : ""
            print("")
            print("\(group.displayName.uppercased()) (\(groupTypes.count))\(marker):")
            if groupTypes.isEmpty {
                print("  (none)")
            }
            for type in groupTypes {
                print("  \(type.id): \(type.description)")
            }
        }

        print("")
        print("Total: \(types.count) activity types")
    }
}
