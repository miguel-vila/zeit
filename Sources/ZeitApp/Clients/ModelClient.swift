import Dependencies
import DependenciesMacros
import Foundation

/// Download progress for a single model
struct ModelProgress: Equatable, Sendable {
    let modelName: String
    let progress: Double
    let status: ModelDownloadStatus
}

// MARK: - Client Interface

@DependencyClient
struct ModelClient: Sendable {
    /// Check if a specific model is downloaded
    var isModelDownloaded: @Sendable (String) async -> Bool = { _ in false }

    /// Check if all required models are downloaded
    var allModelsDownloaded: @Sendable () async -> Bool = { false }

    /// Download a model by config name, reporting progress via callback
    var downloadModel: @Sendable (String, @Sendable @escaping (Double) -> Void) async throws -> Void

    /// Get the list of supported models with their status
    var getModelStatuses: @Sendable () async -> [ModelProgress] = { [] }
}

// MARK: - Dependency Registration

extension DependencyValues {
    var modelClient: ModelClient {
        get { self[ModelClient.self] }
        set { self[ModelClient.self] = newValue }
    }
}

// MARK: - Live Implementation

extension ModelClient: DependencyKey {
    static let liveValue = ModelClient(
        isModelDownloaded: { configName in
            guard let model = MLXModelManager.modelInfo(forConfigName: configName) else {
                return false
            }
            return await MLXModelManager.shared.isModelDownloaded(model: model)
        },
        allModelsDownloaded: {
            await MLXModelManager.shared.allModelsDownloaded()
        },
        downloadModel: { configName, progressHandler in
            guard let model = MLXModelManager.modelInfo(forConfigName: configName) else {
                throw ModelClientError.unknownModel(configName)
            }
            try await MLXModelManager.shared.downloadModel(model, progressHandler: progressHandler)
        },
        getModelStatuses: {
            var statuses: [ModelProgress] = []
            for model in MLXModelManager.supportedModels {
                let status = await MLXModelManager.shared.downloadStatus(for: model)
                statuses.append(ModelProgress(
                    modelName: model.configName,
                    progress: status == .downloaded ? 1.0 : 0.0,
                    status: status
                ))
            }
            return statuses
        }
    )
}

// MARK: - Errors

enum ModelClientError: LocalizedError {
    case unknownModel(String)

    var errorDescription: String? {
        switch self {
        case .unknownModel(let name):
            return "Unknown model: \(name)"
        }
    }
}
