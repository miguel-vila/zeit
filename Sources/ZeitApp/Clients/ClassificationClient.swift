import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Client Interface

/// Access to the classification settings in conf.yml.
///
/// The primary group is the one setting a machine stores about how it groups its
/// time: every other classification fact is derived from the activity types
/// themselves.
@DependencyClient
struct ClassificationClient: Sendable {
    /// The group this machine is judged by.
    var primaryGroup: @Sendable () -> ActivityGroup = {
        ZeitConfig.defaultClassification.primaryGroup
    }

    /// Write the primary group to the config, preserving every other setting.
    var savePrimaryGroup: @Sendable (ActivityGroup) throws -> Void
}

// MARK: - Dependency Registration

extension DependencyValues {
    var classificationClient: ClassificationClient {
        get { self[ClassificationClient.self] }
        set { self[ClassificationClient.self] = newValue }
    }
}

// MARK: - Live Implementation

extension ClassificationClient: DependencyKey {
    static let liveValue = ClassificationClient(
        primaryGroup: {
            ZeitConfig.load().classification.primaryGroup
        },
        savePrimaryGroup: { group in
            try ZeitConfig.savePrimaryGroup(group)
        }
    )
}
