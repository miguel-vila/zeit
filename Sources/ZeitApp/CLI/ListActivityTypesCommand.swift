import ArgumentParser
import Foundation

/// CLI command to list configured activity types.
struct ListActivityTypesCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "list-activity-types",
        abstract: "List configured activity types"
    )

    func run() async throws {
        let db = try DatabaseHelper()
        let types = try await db.getActivityTypes()

        let workTypes = types.filter(\.isWork)
        let personalTypes = types.filter { !$0.isWork }

        print("Activity Types")
        print("=" .repeated(50))
        print("")

        print("WORK ACTIVITIES (\(workTypes.count)):")
        for type in workTypes {
            print("  \(type.id): \(type.description)")
        }

        print("")

        print("PERSONAL ACTIVITIES (\(personalTypes.count)):")
        for type in personalTypes {
            print("  \(type.id): \(type.description)")
        }

        print("")
        print("Total: \(types.count) activity types")
    }
}
